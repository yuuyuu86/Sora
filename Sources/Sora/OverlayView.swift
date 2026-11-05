import SwiftUI

struct OverlayView: View {
    let sim: OverlaySimulation

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            Canvas(rendersAsynchronously: false) { ctx, size in
                _ = tl.date  // 毎フレーム再描画させる
                guard AppSettings.shared.overlayOn else { return }
                draw(&ctx, size)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let a = Atmosphere.shared
        let fx = AppSettings.shared.intensity
        let light = a.light.scaled(min(1, a.brightness + 0.15))
        let snowColor = RGB(0.97, 0.98, 1).mix(light, 0.5)

        // 積雪（背面から描き、前面ウィンドウで隠れる部分は消す）
        let surfaces = sim.surfaces
        for (idx, s) in surfaces.enumerated().reversed() where s.total > 1 {
            ctx.drawLayer { layer in
                var path = Path()
                let n = s.heights.count
                let wobble = s.shake * 2
                path.move(to: CGPoint(x: s.rect.minX + OverlaySimulation.col / 2, y: s.baseY(0) + 1))
                for c in 0..<n {
                    let h = s.heights[c]
                    let x = s.rect.minX + Double(c) * OverlaySimulation.col + OverlaySimulation.col / 2
                    let wy = wobble * sin(Double(c) * 0.7 + a.time * 30)
                    path.addLine(to: CGPoint(x: x, y: s.baseY(c) - h + (h > 0.3 ? wy : 0) + 0.5))
                }
                // 底はウィンドウの角の丸みに沿わせる
                for c in stride(from: n - 1, through: 0, by: -1) {
                    let x = s.rect.minX + Double(c) * OverlaySimulation.col + OverlaySimulation.col / 2
                    path.addLine(to: CGPoint(x: x, y: s.baseY(c) + 1))
                }
                path.closeSubpath()
                layer.fill(path, with: .linearGradient(
                    Gradient(colors: [snowColor.color(0.97), RGB(0.82, 0.86, 0.93).mix(light, 0.4).color(0.95)]),
                    startPoint: CGPoint(x: 0, y: s.rect.minY - 16), endPoint: CGPoint(x: 0, y: s.rect.minY + 1)))
                layer.stroke(path, with: .color(.white.opacity(0.6)), lineWidth: 0.6)
                // 前面のウィンドウで隠す
                if s.id >= 0 {
                    layer.blendMode = .clear
                    for o in surfaces[..<idx] where o.id >= 0 {
                        layer.fill(Path(o.rect), with: .color(.black))
                    }
                }
            }
        }

        // 粒子
        var rain = Path(), snow = Path(), chunk = Path(), splash = Path()
        for q in sim.particles {
            switch q.kind {
            case .rain:
                let len = 0.022
                rain.move(to: CGPoint(x: q.x, y: q.y))
                rain.addLine(to: CGPoint(x: q.x - q.vx * len, y: q.y - q.vy * len))
            case .snow:
                snow.addEllipse(in: CGRect(x: q.x - q.size / 2, y: q.y - q.size / 2, width: q.size, height: q.size))
            case .chunk:
                chunk.addEllipse(in: CGRect(x: q.x - q.size / 2, y: q.y - q.size / 2, width: q.size, height: q.size))
            case .splash, .drip:
                let r = q.size
                splash.addEllipse(in: CGRect(x: q.x - r / 2, y: q.y - r / 2, width: r, height: r * (q.kind == .drip ? 1.4 : 1)))
            }
        }
        let rainCol = RGB(0.8, 0.85, 0.92).mix(light, 0.3)
        ctx.stroke(rain, with: .color(rainCol.color(0.32)), lineWidth: 1)
        ctx.fill(snow, with: .color(snowColor.color(0.85)))
        ctx.fill(chunk, with: .color(snowColor.color(0.95)))
        ctx.fill(splash, with: .color(rainCol.color(0.55)))

        // 霧：画面の端がかすみ、カーソルの通り道は晴れる
        let fog = a.params.fog * (0.4 + 0.6 * fx)
        if fog > 0.02 {
            ctx.drawLayer { layer in
                let c = a.skyHorizon.mix(RGB(0.85, 0.87, 0.9), 0.5)
                let w = size.width, h = size.height, e = min(w, h) * 0.22
                let full = Path(CGRect(origin: .zero, size: size))
                layer.fill(full, with: .color(c.color(fog * 0.08)))
                let edges: [(CGRect, CGPoint, CGPoint)] = [
                    (CGRect(x: 0, y: 0, width: e, height: h), .zero, CGPoint(x: e, y: 0)),
                    (CGRect(x: w - e, y: 0, width: e, height: h), CGPoint(x: w, y: 0), CGPoint(x: w - e, y: 0)),
                    (CGRect(x: 0, y: 0, width: w, height: e), .zero, CGPoint(x: 0, y: e)),
                    (CGRect(x: 0, y: h - e, width: w, height: e), CGPoint(x: 0, y: h), CGPoint(x: 0, y: h - e)),
                ]
                for (r, s, t) in edges {
                    layer.fill(Path(r), with: .linearGradient(Gradient(colors: [c.color(fog * 0.4), c.color(0)]), startPoint: s, endPoint: t))
                }
                layer.blendMode = .destinationOut
                for t in sim.trail {
                    let r = 70.0
                    layer.fill(Path(ellipseIn: CGRect(x: t.p.x - r, y: t.p.y - r, width: r * 2, height: r * 2)),
                               with: .radialGradient(Gradient(colors: [Color.black.opacity(0.8 * t.life), .clear]),
                                                     center: t.p, startRadius: 0, endRadius: r))
                }
            }
        }

        // 雷の光が周囲にも広がる
        if a.flash > 0.01 {
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(Color(red: 0.92, green: 0.95, blue: 1).opacity(a.flash * 0.12 * fx)))
        }
    }
}

import SwiftUI

struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(_ seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// 草原の固定要素（雲・草・星の配置）
final class MeadowLayout {
    struct Cloud { var x, y, scale, speed, density: Double; var puffs: [(dx: Double, dy: Double, r: Double)] }
    struct Blade { var x, height, lean, phase, width, shade: Double; var row: Int }
    struct Star { var x, y, size, phase: Double }

    let clouds: [Cloud]
    let blades: [Blade]
    let stars: [Star]

    init() {
        var g = SeededRandom(42)
        clouds = (0..<18).map { i in
            let n = Int.random(in: 5...9, using: &g)
            return Cloud(
                x: .random(in: 0...1, using: &g), y: .random(in: 0.05...0.42, using: &g),
                scale: .random(in: 0.6...1.4, using: &g), speed: .random(in: 0.004...0.011, using: &g),
                density: Double(i) / 18,
                puffs: (0..<n).map { _ in (.random(in: -1...1, using: &g), .random(in: -0.25...0.2, using: &g), .random(in: 0.35...0.8, using: &g)) })
        }
        blades = (0..<520).map { i in
            let row = i % 3
            return Blade(x: .random(in: -0.02...1.02, using: &g),
                         height: .random(in: 0.05...0.13, using: &g) * (1 + Double(row) * 0.45),
                         lean: .random(in: -0.3...0.3, using: &g), phase: .random(in: 0...6.28, using: &g),
                         width: .random(in: 1.2...2.8, using: &g) * (1 + Double(row) * 0.4),
                         shade: .random(in: 0...1, using: &g), row: row)
        }.sorted { $0.row < $1.row }
        stars = (0..<160).map { _ in
            Star(x: .random(in: 0...1, using: &g), y: .random(in: 0...0.55, using: &g),
                 size: .random(in: 0.5...1.6, using: &g), phase: .random(in: 0...6.28, using: &g))
        }
    }
}

struct LandscapeView: View {
    let layout = MeadowLayout()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
            Canvas(rendersAsynchronously: false) { ctx, size in
                switch AppSettings.shared.landscape {
                case .meadow: drawMeadow(&ctx, size)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func drawMeadow(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let a = Atmosphere.shared
        let p = a.params
        let s = AppSettings.shared
        let w = size.width, h = size.height
        let horizon = h * 0.64
        let full = Path(CGRect(origin: .zero, size: size))
        let night = max(0, -a.sunAltitude) / 1.0
        let fx = 0.4 + 0.6 * s.intensity  // 演出の強さ

        // 空
        ctx.fill(full, with: .linearGradient(Gradient(colors: [a.skyTop.color, a.skyHorizon.color]),
                                             startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))

        // 星
        let starAlpha = max(0, min(1, (night - 0.1) * 2)) * (1 - p.cloud) * (1 - p.fog)
        if starAlpha > 0.01 {
            var stars = Path()
            for st in layout.stars {
                let tw = 0.6 + 0.4 * sin(a.time * 1.5 + st.phase)
                let r = st.size * tw
                stars.addEllipse(in: CGRect(x: st.x * w, y: st.y * horizon, width: r, height: r))
            }
            ctx.fill(stars, with: .color(.white.opacity(0.75 * starAlpha)))
        }

        // 太陽・月（画面の端にうっすら）
        if s.showSunMoon {
            let veil = 1 - min(0.85, p.cloud * 0.8 + p.fog * 0.4)
            if a.sunAltitude > -0.1 {
                let x = w * (0.06 + 0.88 * a.sunProgress)
                let y = horizon - (horizon * 0.78) * max(0, a.sunAltitude) + 12
                let warm = RGB(1, 0.86, 0.6).mix(RGB(1, 0.98, 0.92), a.sunAltitude * 1.5)
                let glowR = 260.0 * (1 + p.cloud)
                ctx.fill(Path(ellipseIn: CGRect(x: x - glowR, y: y - glowR, width: glowR * 2, height: glowR * 2)),
                         with: .radialGradient(Gradient(colors: [warm.color(0.45 * veil), warm.color(0)]),
                                               center: CGPoint(x: x, y: y), startRadius: 0, endRadius: glowR))
                let r = 22.0
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(warm.color(0.85 * veil * veil)))
            } else {
                let x = w * (0.08 + 0.84 * a.moonProgress)
                let y = horizon * 0.85 - horizon * 0.65 * sin(.pi * a.moonProgress)
                let r = 16.0
                ctx.fill(Path(ellipseIn: CGRect(x: x - 120, y: y - 120, width: 240, height: 240)),
                         with: .radialGradient(Gradient(colors: [Color.white.opacity(0.12 * veil), .clear]),
                                               center: CGPoint(x: x, y: y), startRadius: 0, endRadius: 120))
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(Color(red: 0.93, green: 0.95, blue: 1).opacity(0.7 * veil)))
                // 欠け
                ctx.fill(Path(ellipseIn: CGRect(x: x - r + 7, y: y - r - 3, width: r * 2, height: r * 2)),
                         with: .color(a.skyTop.mix(a.skyHorizon, 0.4).color(0.85 * veil)))
            }
        }

        // 雲
        let cloudCol = a.light.scaled(a.brightness).mix(RGB(0.55, 0.58, 0.63), p.rain * 0.6 + p.thunder * 0.3)
        let windSpeed = 0.4 + abs(p.wind) * 2.5
        let dirSign = p.wind >= 0 ? 1.0 : -1.0
        for c in layout.clouds where c.density < p.cloud + 0.08 {
            let fade = min(1, (p.cloud + 0.08 - c.density) * 5)
            let cw = w * 0.22 * c.scale * (1 + p.cloud * 0.6)
            var x = (c.x + dirSign * a.time * c.speed * windSpeed * 0.05).truncatingRemainder(dividingBy: 1.3)
            if x < 0 { x += 1.3 }
            let cx = x * w * 1.0 - 0.15 * w
            let cy = c.y * horizon
            for puff in c.puffs {
                let r = cw * 0.5 * puff.r
                let px = cx + puff.dx * cw * 0.6, py = cy + puff.dy * cw * 0.5
                ctx.fill(Path(ellipseIn: CGRect(x: px - r, y: py - r * 0.7, width: r * 2, height: r * 1.4)),
                         with: .radialGradient(Gradient(colors: [cloudCol.color(0.32 * fade), cloudCol.color(0)]),
                                               center: CGPoint(x: px, y: py), startRadius: 0, endRadius: r))
            }
        }

        // 遠景の丘
        let haze = min(0.9, p.fog * 0.8 + p.rain * 0.45 + p.snow * 0.3)
        let lightK = a.light.scaled(a.brightness)
        let snowK = a.snowGround
        func hill(_ base: Double, _ amp: Double, _ freq: Double, _ seed: Double, _ col: RGB, _ hz: Double) {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: h))
            var x = 0.0
            while x <= w + 20 {
                let u = x / w
                let y = base - amp * (0.55 * sin(u * freq + seed) + 0.3 * sin(u * freq * 2.3 + seed * 1.7) + 0.15 * sin(u * freq * 5.1))
                path.addLine(to: CGPoint(x: x, y: y))
                x += 20
            }
            path.addLine(to: CGPoint(x: w, y: h))
            path.closeSubpath()
            var c = RGB(col.r * lightK.r, col.g * lightK.g, col.b * lightK.b)
            c = c.mix(RGB(0.9, 0.92, 0.95).scaled(a.brightness), snowK * 0.85)
            c = c.mix(a.skyHorizon, hz)
            ctx.fill(path, with: .color(c.color))
        }
        hill(horizon - 8, h * 0.06, 5, 1.3, RGB(0.42, 0.52, 0.55), 0.55 + haze * 0.4)
        hill(horizon + 4, h * 0.035, 7, 4.1, RGB(0.32, 0.45, 0.32), 0.3 + haze * 0.5)

        // 草原
        let g1 = RGB(0.36, 0.55, 0.26), g2 = RGB(0.2, 0.38, 0.14)
        func ground(_ c: RGB) -> RGB {
            RGB(c.r * lightK.r, c.g * lightK.g, c.b * lightK.b).mix(RGB(0.92, 0.94, 0.97).scaled(a.brightness), snowK * 0.9)
        }
        let groundRect = Path(CGRect(x: 0, y: horizon + 6, width: w, height: h - horizon))
        ctx.fill(groundRect, with: .linearGradient(
            Gradient(colors: [ground(g1).mix(a.skyHorizon, haze * 0.35).color, ground(g2).color]),
            startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)))

        // 雲の影
        if p.cloud > 0.25 && p.cloud < 0.9 && a.sunAltitude > 0.1 {
            let k = min(1, (p.cloud - 0.25) * 4) * (1 - max(0, p.cloud - 0.75) * 6.6)
            for (i, c) in layout.clouds.prefix(6).enumerated() {
                var x = (c.x + 0.3 + dirSign * a.time * c.speed * windSpeed * 0.05).truncatingRemainder(dividingBy: 1.3)
                if x < 0 { x += 1.3 }
                let cx = x * w - 0.15 * w
                let cy = horizon + (h - horizon) * (0.25 + 0.12 * Double(i % 3))
                let rw = w * 0.2 * c.scale, rh = (h - horizon) * 0.12
                ctx.fill(Path(ellipseIn: CGRect(x: cx - rw, y: cy - rh, width: rw * 2, height: rh * 2)),
                         with: .radialGradient(Gradient(colors: [Color.black.opacity(0.14 * k), .clear]),
                                               center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: rw))
            }
        }

        // 手前の草（風で揺れる）
        let sway = 0.12 + abs(p.wind) * 0.6 * fx
        for b in layout.blades {
            let depth = Double(b.row) / 2
            let baseY = h - (1 - depth) * (h - horizon) * 0.22 + 6
            let bh = b.height * h * (snowK > 0.6 ? 1 - (snowK - 0.6) * 0.8 : 1)
            let gust = sin(a.time * (1.1 + depth * 0.4) + b.phase + b.x * 6) + 0.5 * sin(a.time * 2.7 + b.phase * 2)
            let bend = (b.lean + p.wind * 0.8 + gust * sway) * bh * 0.6
            let x = b.x * w
            var path = Path()
            path.move(to: CGPoint(x: x - b.width, y: baseY))
            path.addQuadCurve(to: CGPoint(x: x + bend, y: baseY - bh), control: CGPoint(x: x + bend * 0.2, y: baseY - bh * 0.6))
            path.addQuadCurve(to: CGPoint(x: x + b.width, y: baseY), control: CGPoint(x: x + bend * 0.2 + b.width, y: baseY - bh * 0.55))
            path.closeSubpath()
            let col = ground(RGB(0.18, 0.36, 0.12).mix(RGB(0.45, 0.6, 0.25), b.shade * 0.6 + depth * 0.25))
            ctx.fill(path, with: .color(col.color))
        }

        // 霧・雨のかすみ
        if haze > 0.01 {
            ctx.fill(full, with: .linearGradient(
                Gradient(stops: [
                    .init(color: a.skyHorizon.color(0), location: 0.25),
                    .init(color: a.skyHorizon.color(haze * 0.7), location: 0.62),
                    .init(color: a.skyHorizon.color(haze * 0.35), location: 0.85),
                    .init(color: a.skyHorizon.color(haze * 0.15), location: 1),
                ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        }

        // 夜の青み
        if night > 0 {
            ctx.fill(full, with: .color(Color(red: 0.05, green: 0.08, blue: 0.2).opacity(night * 0.35 * s.lightStrength)))
        }

        // 稲妻
        if a.flash > 0.01 {
            ctx.fill(full, with: .color(Color(red: 0.9, green: 0.93, blue: 1).opacity(a.flash * 0.45 * fx)))
        }
    }
}

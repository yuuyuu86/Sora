import AppKit
import SwiftUI

/// 1画面分の雨・雪・積雪・霧のシミュレーション（座標は画面ローカル・左上原点）
final class OverlaySimulation {
    enum Kind { case rain, snow, splash, chunk, drip }

    struct Particle {
        var x, y, vx, vy: Double
        var size: Double
        var kind: Kind
        var life: Double = 0
        var phase: Double = .random(in: 0...6.28)
    }

    /// ウィンドウ上端・Dock 上面
    final class Surface {
        let id: Int              // CGWindowID、Dock は負数
        var rect: CGRect
        var heights: [Double]    // 4px 列ごとの積雪
        var water: Double = 0
        var seen = true
        var shake: Double = 0
        init(id: Int, rect: CGRect) {
            self.id = id; self.rect = rect
            heights = Array(repeating: 0, count: max(1, Int(rect.width / OverlaySimulation.col)))
        }
        func surfaceY(_ x: Double) -> Double {
            rect.minY - heights[col(x)]
        }
        func col(_ x: Double) -> Int {
            max(0, min(heights.count - 1, Int((x - rect.minX) / OverlaySimulation.col)))
        }
        var total: Double { heights.reduce(0, +) }
    }

    static let col: Double = 4

    let screen: NSScreen
    var size: CGSize
    private(set) var particles: [Particle] = []
    /// 前面 → 背面（Dock を先頭に）
    private(set) var surfaces: [Surface] = []
    private var byID: [Int: Surface] = [:]
    private(set) var trail: [(p: CGPoint, life: Double)] = []
    private var mouse = CGPoint(x: -999, y: -999)
    private var mouseV = CGVector()
    private var hadMouse = false
    var onSplash: (() -> Void)?

    init(screen: NSScreen) {
        self.screen = screen
        size = screen.frame.size
    }

    // MARK: - Step

    func step(dt: Double) {
        let a = Atmosphere.shared
        let p = a.params
        let fx = AppSettings.shared.intensity
        size = screen.frame.size

        updateSurfaces(dt: dt)
        updateMouse(dt: dt)

        // 粒子の生成
        let rainTarget = Int(520 * p.rain * fx)
        let snowTarget = Int(380 * p.snow * fx)
        var rainCount = 0, snowCount = 0
        for q in particles { if q.kind == .rain { rainCount += 1 } else if q.kind == .snow { snowCount += 1 } }
        let windShift = p.wind * size.height * 0.4
        for _ in 0..<min(40, max(0, rainTarget - rainCount)) {
            particles.append(Particle(x: .random(in: min(0, -windShift)...max(size.width, size.width - windShift)),
                                      y: .random(in: -200 ... -10), vx: p.wind * 260, vy: .random(in: 900...1250),
                                      size: .random(in: 0.7...1.3), kind: .rain))
        }
        for _ in 0..<min(10, max(0, snowTarget - snowCount)) {
            particles.append(Particle(x: .random(in: min(0, -windShift * 0.3)...max(size.width, size.width - windShift * 0.3)),
                                      y: .random(in: -60 ... -5), vx: p.wind * 70, vy: .random(in: 35...85),
                                      size: .random(in: 1.5...3.8), kind: .snow))
        }

        let maxSnow = 4 + 14 * fx
        var i = 0
        while i < particles.count {
            var q = particles[i]
            let oldY = q.y
            q.life += dt
            switch q.kind {
            case .rain:
                q.vx += (p.wind * 260 - q.vx) * dt * 2
            case .snow:
                q.vx += (p.wind * 70 + sin(a.time * 1.3 + q.phase) * 18 - q.vx) * dt * 1.5
                q.vy += (60 * (q.size / 2.5) - q.vy) * dt
            case .splash, .chunk, .drip:
                q.vy += 1400 * dt * (q.kind == .chunk ? 0.75 : 1)
                q.vx *= 1 - dt * (q.kind == .chunk ? 0.6 : 2)
            }
            applyCursor(&q, dt: dt)
            q.x += q.vx * dt
            q.y += q.vy * dt

            var remove = q.y > size.height + 20 || q.x < -300 || q.x > size.width + 300
            if q.kind == .splash && q.life > 0.35 { remove = true }

            if !remove, q.kind != .splash, q.vy > 0, let s = hitSurface(x: q.x, oldY: oldY, newY: q.y) {
                remove = land(q, on: s, maxSnow: maxSnow)
                if !remove { q.y = s.surfaceY(q.x) - 1 }
            }

            if remove {
                particles.swapAt(i, particles.count - 1)
                particles.removeLast()
            } else {
                particles[i] = q
                i += 1
            }
        }

        // 積雪をならす・端からこぼれる・雨で溶ける
        for s in surfaces { relax(s, dt: dt, rain: p.rain) }

        // 霧の通り道
        for k in trail.indices { trail[k].life -= dt * 0.35 }
        trail.removeAll { $0.life <= 0 }
    }

    /// 衝突した面（前面にある・遮られていない）
    private func hitSurface(x: Double, oldY: Double, newY: Double) -> Surface? {
        for s in surfaces where x >= s.rect.minX && x <= s.rect.maxX {
            let sy = s.surfaceY(x)
            if oldY <= sy && newY >= sy && !occluded(CGPoint(x: x, y: sy), below: s) { return s }
        }
        return nil
    }

    /// s より前面のウィンドウが点を覆っているか
    func occluded(_ pt: CGPoint, below s: Surface) -> Bool {
        if s.id < 0 { return false }
        for o in surfaces {
            if o === s { return false }
            if o.id >= 0 && o.rect.contains(pt) { return true }
        }
        return false
    }

    /// 面に着地。粒子を消すなら true
    private func land(_ q: Particle, on s: Surface, maxSnow: Double) -> Bool {
        let c = s.col(q.x)
        switch q.kind {
        case .rain, .drip:
            // 小さく跳ねる
            let n = q.kind == .drip ? 3 : Int.random(in: 1...2)
            for _ in 0..<n {
                particles.append(Particle(x: q.x, y: s.surfaceY(q.x) - 1, vx: .random(in: -60...60),
                                          vy: .random(in: -170 ... -60), size: .random(in: 0.8...1.4), kind: .splash))
            }
            s.water += 1
            if s.heights[c] > 0 { s.heights[c] = max(0, s.heights[c] - 0.15) }
            if Double.random(in: 0...1) < 0.02 { onSplash?() }
            return true
        case .snow:
            s.heights[c] = min(maxSnow * 1.3, s.heights[c] + q.size * 0.35)
            return true
        case .chunk:
            s.heights[c] = min(maxSnow * 1.5, s.heights[c] + q.size * 0.9)
            // 小さく舞う
            if q.vy > 200 {
                particles.append(Particle(x: q.x, y: s.surfaceY(q.x) - 2, vx: .random(in: -40...40),
                                          vy: .random(in: -90 ... -30), size: 1.2, kind: .splash))
            }
            return true
        case .splash:
            return true
        }
    }

    private func relax(_ s: Surface, dt: Double, rain: Double) {
        let n = s.heights.count
        guard n > 1 else { return }
        // 安息角を超えた分を隣へ
        for _ in 0..<2 {
            for c in 0..<(n - 1) {
                let d = s.heights[c] - s.heights[c + 1]
                if abs(d) > 2.2 {
                    let m = (abs(d) - 2.2) * 0.3 * (d > 0 ? 1 : -1)
                    s.heights[c] -= m
                    s.heights[c + 1] += m
                }
            }
        }
        // 端からこぼれる
        for c in [0, n - 1] where s.heights[c] > 2.5 && Double.random(in: 0...1) < dt * 2 {
            let amt = min(s.heights[c], .random(in: 1...3))
            s.heights[c] -= amt
            let x = c == 0 ? s.rect.minX - 2 : s.rect.maxX + 2
            spawnChunk(x: x, y: s.rect.minY - amt, vx: c == 0 ? -20 : 20, vy: 0, size: amt)
        }
        // 揺れ（ウィンドウ移動後）
        s.shake = max(0, s.shake - dt * 3)
        // 雨で溶ける
        if rain > 0.1 { for c in 0..<n { s.heights[c] = max(0, s.heights[c] - dt * rain * 0.3) } }
        // 強い雨のとき、水滴がまとまって端から落ちる
        if s.water > 25 && rain > 0.45 {
            s.water = 0
            let left = Bool.random()
            particles.append(Particle(x: left ? s.rect.minX + 2 : s.rect.maxX - 2, y: s.rect.minY + 2,
                                      vx: left ? -15 : 15, vy: 30, size: 2.6, kind: .drip))
        }
        s.water = max(0, s.water - dt * 2)
    }

    private func spawnChunk(x: Double, y: Double, vx: Double, vy: Double, size: Double) {
        guard particles.count < 2500 else { return }
        particles.append(Particle(x: x, y: y, vx: vx, vy: vy, size: max(1.2, min(4.5, size)), kind: .chunk))
    }

    /// 面の雪を粒にして落とす
    private func release(_ s: Surface, fraction: Double, vx: Double, vy: Double, spread: Double) {
        for c in s.heights.indices where s.heights[c] > 0.5 {
            let take = s.heights[c] * fraction
            guard take > 0.3 else { continue }
            s.heights[c] -= take
            if c % 2 == 0 || take > 2 {
                let x = s.rect.minX + Double(c) * Self.col + 2
                spawnChunk(x: x, y: s.rect.minY - s.heights[c] - take * 0.5,
                           vx: vx + .random(in: -spread...spread), vy: vy + .random(in: -spread...spread * 0.4), size: take * 1.4)
            }
        }
    }

    // MARK: - Windows

    private func updateSurfaces(dt: Double) {
        let tracker = WindowTracker.shared
        for s in byID.values { s.seen = false }
        var ordered: [Surface] = []
        let bounds = CGRect(origin: .zero, size: size)

        // Dock（画面下にある場合）
        let f = screen.frame, v = screen.visibleFrame
        let dockH = v.minY - f.minY
        if dockH > 8 {
            var dock = CGRect(x: size.width * 0.2, y: size.height - dockH, width: size.width * 0.6, height: dockH)
            for r in tracker.dockRects {
                let l = WindowTracker.toLocal(r, screen: screen)
                if l.height < size.height * 0.4 && l.maxY >= size.height - 2 && l.width < size.width * 0.98 && l.intersects(bounds) {
                    dock = l; break
                }
            }
            ordered.append(surface(id: -1, rect: dock, dt: dt))
        }

        for w in tracker.windows {
            let l = WindowTracker.toLocal(w.rect, screen: screen)
            guard l.intersects(bounds), l.minY > 20 || l.maxY > 40 else { continue }
            ordered.append(surface(id: Int(w.id), rect: l, dt: dt))
        }

        // 消えたウィンドウ：雪が舞い落ちる
        for (id, s) in byID where !s.seen {
            release(s, fraction: 1, vx: 0, vy: -60, spread: 90)
            byID[id] = nil
        }
        surfaces = ordered
    }

    private func surface(id: Int, rect: CGRect, dt: Double) -> Surface {
        if let s = byID[id] {
            s.seen = true
            let dx = rect.minX - s.rect.minX, dy = rect.minY - s.rect.minY
            if abs(rect.width - s.rect.width) > 1 {
                // リサイズ：積雪を引き伸ばす
                let n = max(1, Int(rect.width / Self.col))
                let old = s.heights
                s.heights = (0..<n).map { old[min(old.count - 1, $0 * old.count / n)] }
            }
            s.rect = rect
            if dt > 0, abs(dx) + abs(dy) > 0.5 {
                let vx = dx / dt, vy = dy / dt
                let speed = hypot(vx, vy)
                if speed > 60 {
                    // 動かすと揺れて崩れる（少し強調）
                    s.shake = min(1, s.shake + speed / 2000)
                    let frac = min(0.6, speed / 4000) + (vy < -300 ? 0.2 : 0)
                    release(s, fraction: frac, vx: -vx * 0.15, vy: min(0, vy) * 0.2 - 40, spread: 50)
                }
            }
            return s
        }
        let s = Surface(id: id, rect: rect)
        byID[id] = s
        return s
    }

    // MARK: - Cursor

    private func updateMouse(dt: Double) {
        let m = NSEvent.mouseLocation
        let f = screen.frame
        let local = CGPoint(x: m.x - f.minX, y: f.maxY - m.y)
        let inside = f.contains(m)
        if inside, hadMouse, dt > 0 {
            let nv = CGVector(dx: (local.x - mouse.x) / dt, dy: (local.y - mouse.y) / dt)
            mouseV = CGVector(dx: mouseV.dx * 0.5 + nv.dx * 0.5, dy: mouseV.dy * 0.5 + nv.dy * 0.5)
        } else {
            mouseV = CGVector()
        }
        mouse = inside ? local : CGPoint(x: -999, y: -999)
        hadMouse = inside

        let speed = hypot(mouseV.dx, mouseV.dy)
        guard inside, speed > 15 else { return }

        // 霧を晴らす
        if Atmosphere.shared.params.fog > 0.05 {
            if let last = trail.last, hypot(last.p.x - local.x, last.p.y - local.y) < 14 { } else {
                trail.append((local, 1))
                if trail.count > 160 { trail.removeFirst() }
            }
        }

        // 積もった雪を払う
        let radius = 16 + min(30, speed / 60)
        for s in surfaces {
            guard local.x > s.rect.minX - radius, local.x < s.rect.maxX + radius,
                  local.y > s.rect.minY - 30, local.y < s.rect.minY + 10 else { continue }
            if occluded(CGPoint(x: local.x, y: s.rect.minY - 1), below: s) { continue }
            let c0 = s.col(local.x - radius), c1 = s.col(local.x + radius)
            let fast = speed > 700
            for c in c0...c1 {
                let h = s.heights[c]
                guard h > 0.4 else { continue }
                let top = s.rect.minY - h
                guard local.y > top - 8 else { continue }
                let take = fast ? h : h * min(0.5, speed / 1500 + 0.15)
                s.heights[c] -= take
                let x = s.rect.minX + Double(c) * Self.col + 2
                if fast {
                    // 素早く動かすと大きく舞う
                    for _ in 0..<2 {
                        spawnChunk(x: x, y: top, vx: mouseV.dx * .random(in: 0.25...0.6),
                                   vy: -abs(mouseV.dy) * 0.3 - .random(in: 150...420), size: take * 0.8)
                    }
                } else if c % 2 == 0 {
                    spawnChunk(x: x, y: top, vx: mouseV.dx * 0.25 + .random(in: -20...20),
                               vy: .random(in: -60...0), size: take * 1.3)
                }
            }
        }
    }

    private func applyCursor(_ q: inout Particle, dt: Double) {
        guard hadMouse else { return }
        let dx = q.x - mouse.x, dy = q.y - mouse.y
        let d2 = dx * dx + dy * dy
        let r: Double = q.kind == .rain ? 22 : 45
        guard d2 < r * r, d2 > 0.01 else { return }
        let d = sqrt(d2), k = 1 - d / r
        switch q.kind {
        case .snow, .chunk:
            q.vx += (dx / d * 240 + mouseV.dx * 0.8) * k * dt * 6
            q.vy += (dy / d * 160 + mouseV.dy * 0.8) * k * dt * 6
        case .rain:
            q.vx += dx / d * 300 * k * dt * 4   // 控えめに
        default: break
        }
    }
}

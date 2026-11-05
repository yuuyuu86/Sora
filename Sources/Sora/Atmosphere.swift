import Foundation
import SwiftUI

/// 簡易 RGB（補間用）
struct RGB {
    var r, g, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xff) / 255; g = Double((hex >> 8) & 0xff) / 255; b = Double(hex & 0xff) / 255
    }
    func mix(_ o: RGB, _ t: Double) -> RGB {
        let t = max(0, min(1, t))
        return RGB(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t)
    }
    func scaled(_ s: Double) -> RGB { RGB(r * s, g * s, b * s) }
    var color: Color { Color(red: r, green: g, blue: b) }
    func color(_ a: Double) -> Color { Color(red: r, green: g, blue: b, opacity: a) }
}

/// 時刻と天気から決まる、画面全体で共有する「空気」の状態。
final class Atmosphere {
    static let shared = Atmosphere()

    var params = WeatherParams()          // 補間済みの現在値
    var time: Double = 0                  // 経過秒
    var snowGround: Double = 0            // 草原の積雪 0…1
    var flash: Double = 0                 // 稲妻の明るさ 0…1
    var onThunder: (() -> Void)?

    // 光
    var sunAltitude: Double = 0.5         // -1…1
    var sunProgress: Double = 0.5         // 日中 0(日の出)…1(日の入り)
    var moonProgress: Double = 0.5        // 夜間 0…1
    var skyTop = RGB(hex: 0x4d7fc4)
    var skyHorizon = RGB(hex: 0xbcd6ea)
    var light = RGB(1, 1, 1)              // 景色に乗る光の色
    var brightness: Double = 1

    private var pendingThunder: Double = -1

    var target: WeatherParams {
        let s = AppSettings.shared
        if s.autoWeather, let r = WeatherService.shared.report { return r.params }
        return .preset(s.manualWeather, wind: s.manualWind)
    }

    var displayKind: WeatherKind {
        let s = AppSettings.shared
        if s.autoWeather { return WeatherService.shared.report?.kind ?? .clear }
        return s.manualWeather
    }

    func step(dt: Double) {
        time += dt
        // 天気は数十秒かけてゆっくり移り変わる
        params.approach(target, rate: min(1, dt * 0.08))

        // 積雪：降雪中は増え、それ以外では溶ける
        if params.snow > 0.15 { snowGround = min(1, snowGround + dt * params.snow * 0.01) }
        else { snowGround = max(0, snowGround - dt * 0.004 * (1 + params.rain * 4)) }

        // 雷
        flash = max(0, flash - dt * 3.5)
        if params.thunder > 0.3, Double.random(in: 0...1) < dt * 0.07 * params.thunder {
            flash = 1
            pendingThunder = time + Double.random(in: 0.6...2.5)
        }
        if pendingThunder > 0, time >= pendingThunder {
            pendingThunder = -1
            onThunder?()
        }
        if flash > 0.5, Double.random(in: 0...1) < dt * 6 { flash = min(1, flash + 0.4) } // ちらつき

        updateLight()
    }

    /// 確認用に時刻を固定する（nil なら現在時刻）
    var debugHour: Double?

    private func updateLight() {
        var now = Date()
        if let hr = debugHour {
            now = Calendar.current.startOfDay(for: now).addingTimeInterval(hr * 3600)
        }
        let cal = Calendar.current
        let rep = WeatherService.shared.report
        var sunrise = rep?.sunrise ?? cal.date(bySettingHour: 6, minute: 0, second: 0, of: now)!
        var sunset = rep?.sunset ?? cal.date(bySettingHour: 18, minute: 0, second: 0, of: now)!
        // 取得日と今日がずれた場合は時刻だけを使う
        if !cal.isDate(sunrise, inSameDayAs: now) {
            let c1 = cal.dateComponents([.hour, .minute], from: sunrise)
            let c2 = cal.dateComponents([.hour, .minute], from: sunset)
            sunrise = cal.date(bySettingHour: c1.hour ?? 6, minute: c1.minute ?? 0, second: 0, of: now)!
            sunset = cal.date(bySettingHour: c2.hour ?? 18, minute: c2.minute ?? 0, second: 0, of: now)!
        }
        let day = sunset.timeIntervalSince(sunrise)
        let t = now.timeIntervalSince(sunrise)
        if t >= 0 && t <= day {
            sunProgress = t / day
            sunAltitude = sin(.pi * sunProgress)
        } else {
            let night = 86400 - day
            var nt = t > day ? t - day : t + night
            nt = max(0, min(night, nt))
            moonProgress = nt / night
            sunAltitude = -sin(.pi * moonProgress)
            sunProgress = t > day ? 1 : 0
        }

        // パレット（夜・朝夕・昼）
        let nightTop = RGB(hex: 0x0b1530), nightHor = RGB(hex: 0x24365a)
        let goldTop = RGB(hex: 0x4a6ea8), goldHor = RGB(hex: 0xf2b27a)
        let dayTop = RGB(hex: 0x3f78c8), dayHor = RGB(hex: 0xc4dcef)
        let a = sunAltitude
        var top: RGB, hor: RGB, lt: RGB, br: Double
        if a < -0.12 {
            top = nightTop; hor = nightHor; lt = RGB(0.55, 0.62, 0.85); br = 0.38
        } else if a < 0.25 {
            let k = (a + 0.12) / 0.37
            let g1 = k < 0.5 ? k * 2 : 1.0
            top = nightTop.mix(goldTop, g1).mix(dayTop, max(0, k - 0.5) * 2)
            hor = nightHor.mix(goldHor, g1).mix(dayHor, max(0, k - 0.5) * 1.6)
            lt = RGB(0.55, 0.62, 0.85).mix(RGB(1.0, 0.82, 0.62), g1).mix(RGB(1, 0.97, 0.92), max(0, k - 0.5) * 2)
            br = 0.38 + 0.55 * k
        } else {
            let k = min(1, (a - 0.25) / 0.5)
            top = dayTop.mix(RGB(hex: 0x2f6cc0), k); hor = dayHor
            lt = RGB(1, 0.97, 0.92).mix(RGB(1, 1, 1), k); br = 0.93 + 0.07 * k
        }

        // 曇り・雨で灰色に、光は弱く
        let overcast = max(params.cloud - 0.3, 0) / 0.7 * 0.85 + params.rain * 0.15
        let gray = RGB(0.62, 0.66, 0.7).scaled(max(br, 0.35))
        top = top.mix(gray, overcast * 0.9)
        hor = hor.mix(gray.scaled(1.08), overcast * 0.8)
        lt = lt.mix(RGB(0.85, 0.88, 0.92), overcast * 0.7)
        br *= 1 - overcast * 0.3

        // 光や色の変化の強さ：弱いほど穏やかな昼の色へ寄せる
        let st = AppSettings.shared.lightStrength
        let neutralTop = RGB(hex: 0x5b88c4), neutralHor = RGB(hex: 0xc8d9e6)
        skyTop = neutralTop.mix(top, st)
        skyHorizon = neutralHor.mix(hor, st)
        light = RGB(1, 1, 1).mix(lt, st)
        brightness = 0.9 + (br - 0.9) * st
    }
}

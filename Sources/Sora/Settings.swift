import Foundation
import Observation

enum WeatherKind: String, CaseIterable, Identifiable, Codable {
    case clear, cloudy, rain, snow, fog, thunder
    var id: String { rawValue }

    var label: String {
        switch self {
        case .clear: "晴れ"
        case .cloudy: "曇り"
        case .rain: "雨"
        case .snow: "雪"
        case .fog: "霧"
        case .thunder: "雷"
        }
    }

    var symbol: String {
        switch self {
        case .clear: "sun.max"
        case .cloudy: "cloud"
        case .rain: "cloud.rain"
        case .snow: "cloud.snow"
        case .fog: "cloud.fog"
        case .thunder: "cloud.bolt.rain"
        }
    }
}

/// 背景の種類。将来ここに風景を追加する。
enum LandscapeKind: String, CaseIterable, Identifiable {
    case meadow
    var id: String { rawValue }
    var label: String {
        switch self {
        case .meadow: "草原"
        }
    }
}

@Observable
final class AppSettings {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    var autoWeather: Bool { didSet { d.set(autoWeather, forKey: "autoWeather") } }
    var manualWeather: WeatherKind { didSet { d.set(manualWeather.rawValue, forKey: "manualWeather") } }
    /// 手動時の風（-1 左向き … 1 右向き）
    var manualWind: Double { didSet { d.set(manualWind, forKey: "manualWind") } }

    var useCurrentLocation: Bool { didSet { d.set(useCurrentLocation, forKey: "useCurrentLocation") } }
    var manualPlaceName: String { didSet { d.set(manualPlaceName, forKey: "manualPlaceName") } }
    var manualLatitude: Double { didSet { d.set(manualLatitude, forKey: "manualLatitude") } }
    var manualLongitude: Double { didSet { d.set(manualLongitude, forKey: "manualLongitude") } }

    /// 演出全体の強さ 0…1
    var intensity: Double { didSet { d.set(intensity, forKey: "intensity") } }
    var showSunMoon: Bool { didSet { d.set(showSunMoon, forKey: "showSunMoon") } }
    /// 光や色の変化の強さ 0…1
    var lightStrength: Double { didSet { d.set(lightStrength, forKey: "lightStrength") } }
    var soundOn: Bool { didSet { d.set(soundOn, forKey: "soundOn") } }
    var landscape: LandscapeKind { didSet { d.set(landscape.rawValue, forKey: "landscape") } }
    /// 天気の上に重ねるウィンドウ・Dockの演出
    var overlayOn: Bool { didSet { d.set(overlayOn, forKey: "overlayOn") } }

    private init() {
        d.register(defaults: [
            "autoWeather": true,
            "manualWeather": WeatherKind.snow.rawValue,
            "manualWind": 0.2,
            "useCurrentLocation": true,
            "manualPlaceName": "東京",
            "manualLatitude": 35.6812,
            "manualLongitude": 139.7671,
            "intensity": 0.7,
            "showSunMoon": true,
            "lightStrength": 0.8,
            "soundOn": false,
            "landscape": LandscapeKind.meadow.rawValue,
            "overlayOn": true,
        ])
        autoWeather = d.bool(forKey: "autoWeather")
        manualWeather = WeatherKind(rawValue: d.string(forKey: "manualWeather") ?? "") ?? .snow
        manualWind = d.double(forKey: "manualWind")
        useCurrentLocation = d.bool(forKey: "useCurrentLocation")
        manualPlaceName = d.string(forKey: "manualPlaceName") ?? "東京"
        manualLatitude = d.double(forKey: "manualLatitude")
        manualLongitude = d.double(forKey: "manualLongitude")
        intensity = d.double(forKey: "intensity")
        showSunMoon = d.bool(forKey: "showSunMoon")
        lightStrength = d.double(forKey: "lightStrength")
        soundOn = d.bool(forKey: "soundOn")
        landscape = LandscapeKind(rawValue: d.string(forKey: "landscape") ?? "") ?? .meadow
        overlayOn = d.bool(forKey: "overlayOn")
    }
}

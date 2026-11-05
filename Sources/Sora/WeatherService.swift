import Foundation
import CoreLocation
import Observation

/// 連続値で表した天気。切り替え時はこの値を徐々に補間する。
struct WeatherParams: Equatable {
    var cloud: Double = 0.2     // 雲量 0…1
    var rain: Double = 0        // 降雨 0…1
    var snow: Double = 0        // 降雪 0…1
    var fog: Double = 0         // 霧 0…1
    var thunder: Double = 0     // 雷 0…1
    var wind: Double = 0.1      // 横風 -1…1（正 = 右向き）

    static func preset(_ kind: WeatherKind, wind: Double) -> WeatherParams {
        var p = WeatherParams(wind: wind)
        switch kind {
        case .clear: p.cloud = 0.3
        case .cloudy: p.cloud = 0.85
        case .rain: p.cloud = 0.9; p.rain = 0.6
        case .snow: p.cloud = 0.8; p.snow = 0.65
        case .fog: p.cloud = 0.55; p.fog = 0.85
        case .thunder: p.cloud = 1; p.rain = 0.85; p.thunder = 1
        }
        return p
    }

    mutating func approach(_ t: WeatherParams, rate: Double) {
        func a(_ v: inout Double, _ to: Double) { v += (to - v) * rate }
        a(&cloud, t.cloud); a(&rain, t.rain); a(&snow, t.snow)
        a(&fog, t.fog); a(&thunder, t.thunder); a(&wind, t.wind)
    }
}

struct WeatherReport {
    var kind: WeatherKind
    var params: WeatherParams
    var temperature: Double?
    var sunrise: Date
    var sunset: Date
    var fetchedAt: Date
}

@Observable
final class WeatherService: NSObject, CLLocationManagerDelegate {
    static let shared = WeatherService()

    var report: WeatherReport?
    var placeName: String = "—"
    var status: String = "取得中…"
    var searchResults: [Place] = []

    struct Place: Identifiable, Hashable {
        var id: String { "\(latitude),\(longitude)" }
        var name: String
        var detail: String
        var latitude: Double
        var longitude: Double
    }

    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var timer: Timer?

    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        refreshLocation()
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            self?.refreshLocation()
        }
    }

    func refreshLocation() {
        let s = AppSettings.shared
        if s.useCurrentLocation {
            switch locationManager.authorizationStatus {
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
            case .authorized, .authorizedAlways:
                locationManager.requestLocation()
            default:
                // 位置情報が使えない場合は手動地点（既定：東京）
                fetch(lat: s.manualLatitude, lon: s.manualLongitude, name: s.manualPlaceName + "（位置情報オフ）")
            }
        } else {
            fetch(lat: s.manualLatitude, lon: s.manualLongitude, name: s.manualPlaceName)
        }
    }

    // MARK: CLLocationManagerDelegate
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        lastLocation = loc
        CLGeocoder().reverseGeocodeLocation(loc) { [weak self] marks, _ in
            let name = marks?.first?.locality ?? marks?.first?.name ?? "現在地"
            self?.fetch(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, name: name)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let s = AppSettings.shared
        fetch(lat: s.manualLatitude, lon: s.manualLongitude, name: s.manualPlaceName + "（現在地不明）")
    }

    // MARK: Open-Meteo
    func fetch(lat: Double, lon: Double, name: String) {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", lat)),
            .init(name: "longitude", value: String(format: "%.4f", lon)),
            .init(name: "current", value: "weather_code,precipitation,wind_speed_10m,wind_direction_10m,cloud_cover,temperature_2m"),
            .init(name: "daily", value: "sunrise,sunset"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "1"),
        ]
        URLSession.shared.dataTask(with: c.url!) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let data, let r = try? JSONDecoder().decode(ForecastResponse.self, from: data) else {
                    self.status = "天気を取得できませんでした" + (error.map { "（\($0.localizedDescription)）" } ?? "")
                    return
                }
                self.placeName = name
                self.report = Self.makeReport(r)
                self.status = "更新 " + Date().formatted(date: .omitted, time: .shortened)
            }
        }.resume()
    }

    func search(_ query: String) {
        guard !query.isEmpty else { searchResults = []; return }
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [.init(name: "name", value: query), .init(name: "count", value: "6"), .init(name: "language", value: "ja")]
        URLSession.shared.dataTask(with: c.url!) { [weak self] data, _, _ in
            let r = data.flatMap { try? JSONDecoder().decode(GeoResponse.self, from: $0) }
            DispatchQueue.main.async {
                self?.searchResults = (r?.results ?? []).map {
                    Place(name: $0.name, detail: [$0.admin1, $0.country].compactMap { $0 }.joined(separator: ", "),
                          latitude: $0.latitude, longitude: $0.longitude)
                }
            }
        }.resume()
    }

    func choose(_ p: Place) {
        let s = AppSettings.shared
        s.manualPlaceName = p.name
        s.manualLatitude = p.latitude
        s.manualLongitude = p.longitude
        s.useCurrentLocation = false
        searchResults = []
        refreshLocation()
    }

    private static func makeReport(_ r: ForecastResponse) -> WeatherReport {
        let code = r.current.weather_code
        let kind: WeatherKind
        switch code {
        case 0, 1: kind = .clear
        case 2, 3: kind = .cloudy
        case 45, 48: kind = .fog
        case 51...67, 80...82: kind = .rain
        case 71...77, 85, 86: kind = .snow
        case 95...99: kind = .thunder
        default: kind = .cloudy
        }
        // 風向（吹いてくる方向）から画面上の横成分へ
        let dir = r.current.wind_direction_10m * .pi / 180
        let wind = max(-1, min(1, -sin(dir) * r.current.wind_speed_10m / 35))
        var p = WeatherParams.preset(kind, wind: wind)
        p.cloud = max(p.cloud * 0.5, min(1, r.current.cloud_cover / 100))
        if p.rain > 0 { p.rain = min(1, 0.35 + r.current.precipitation / 6) }
        if p.snow > 0 { p.snow = min(1, 0.4 + r.current.precipitation / 3) }

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: r.utc_offset_seconds)
        let cal = Calendar.current
        let sunrise = r.daily.sunrise.first.flatMap(f.date) ?? cal.date(bySettingHour: 6, minute: 0, second: 0, of: Date())!
        let sunset = r.daily.sunset.first.flatMap(f.date) ?? cal.date(bySettingHour: 18, minute: 0, second: 0, of: Date())!
        return WeatherReport(kind: kind, params: p, temperature: r.current.temperature_2m,
                             sunrise: sunrise, sunset: sunset, fetchedAt: Date())
    }
}

private struct ForecastResponse: Decodable {
    struct Current: Decodable {
        var weather_code: Int
        var precipitation: Double
        var wind_speed_10m: Double
        var wind_direction_10m: Double
        var cloud_cover: Double
        var temperature_2m: Double?
    }
    struct Daily: Decodable {
        var sunrise: [String]
        var sunset: [String]
    }
    var utc_offset_seconds: Int
    var current: Current
    var daily: Daily
}

private struct GeoResponse: Decodable {
    struct R: Decodable {
        var name: String
        var latitude: Double
        var longitude: Double
        var country: String?
        var admin1: String?
    }
    var results: [R]?
}

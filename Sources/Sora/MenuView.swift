import SwiftUI

struct MenuView: View {
    @Bindable var s = AppSettings.shared
    var weather = WeatherService.shared
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 現在の天気
            HStack(spacing: 10) {
                Image(systemName: Atmosphere.shared.displayKind.symbol)
                    .font(.system(size: 26)).frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.autoWeather ? weather.report?.kind.label ?? "—" : s.manualWeather.label + "（手動）")
                        .font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { weather.refreshLocation() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("天気を更新")
            }

            Divider()

            // 天気
            Toggle("現在地の天気に連動", isOn: $s.autoWeather)
            if !s.autoWeather {
                Picker("天気", selection: $s.manualWeather) {
                    ForEach(WeatherKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                slider("風", value: $s.manualWind, range: -1...1)
            }

            Divider()

            // 場所
            Toggle("現在地を使う", isOn: $s.useCurrentLocation)
                .onChange(of: s.useCurrentLocation) { weather.refreshLocation() }
            if !s.useCurrentLocation {
                HStack {
                    TextField("都市を検索", text: $query).textFieldStyle(.roundedBorder)
                        .onSubmit { weather.search(query) }
                    Button("検索") { weather.search(query) }
                }
                ForEach(weather.searchResults) { p in
                    Button { weather.choose(p); query = "" } label: {
                        VStack(alignment: .leading) {
                            Text(p.name)
                            Text(p.detail).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.borderless)
                }
            }

            Divider()

            // 演出
            slider("演出の強さ", value: $s.intensity, range: 0...1)
            slider("光や色の変化", value: $s.lightStrength, range: 0...1)
            Toggle("太陽・月を表示", isOn: $s.showSunMoon)
            Toggle("ウィンドウ・Dockへの演出", isOn: $s.overlayOn)
            Toggle("音", isOn: $s.soundOn)
            Picker("背景", selection: $s.landscape) {
                ForEach(LandscapeKind.allCases) { Text($0.label).tag($0) }
            }

            Divider()

            HStack {
                Text("Sora").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("終了") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var subtitle: String {
        var parts = [weather.placeName]
        if let t = weather.report?.temperature { parts.append(String(format: "%.0f℃", t)) }
        parts.append(weather.status)
        return parts.joined(separator: " · ")
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).frame(width: 96, alignment: .leading)
            Slider(value: value, in: range)
        }
    }
}

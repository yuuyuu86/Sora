import AppKit
import SwiftUI

@main
struct SoraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView()
        } label: {
            Image(systemName: Atmosphere.shared.displayKind.symbol)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 確認用: Sora --snapshot out.png <weather> <hour>
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), args.count > i + 3 {
            let a = Atmosphere.shared
            let kind = WeatherKind(rawValue: args[i + 2]) ?? .clear
            a.params = .preset(kind, wind: 0.3)
            a.snowGround = kind == .snow ? 1 : 0
            a.debugHour = Double(args[i + 3])
            a.time = 10
            a.step(dt: 0)
            a.params = .preset(kind, wind: 0.3)
            MetalLandscapeView(sceneFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))?
                .snapshot(size: CGSize(width: 1440, height: 900), to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        NSApp.setActivationPolicy(.accessory)
        SceneController.shared.start()
        WeatherService.shared.start()
    }
}

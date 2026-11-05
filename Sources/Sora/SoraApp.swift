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
        NSApp.setActivationPolicy(.accessory)
        SceneController.shared.start()
        WeatherService.shared.start()
    }
}

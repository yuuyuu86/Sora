import AppKit
import SwiftUI

/// 画面ごとに「背景ウィンドウ」と「天気オーバーレイ」を配置し、毎フレーム更新する
final class SceneController {
    static let shared = SceneController()

    private struct Pair {
        let screen: NSScreen
        let background: NSWindow
        let overlay: NSWindow
        let sim: OverlaySimulation
    }

    private var pairs: [Pair] = []
    private var timer: Timer?
    private var last = CACurrentMediaTime()
    private var paused = false

    func start() {
        rebuild()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.rebuild() }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.paused = true }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.paused = false; self?.last = CACurrentMediaTime()
        }
        Atmosphere.shared.onThunder = { SoundEngine.shared.thunder() }

        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - last)
        last = now
        guard !paused else { return }
        let s = AppSettings.shared
        Atmosphere.shared.step(dt: dt)
        SoundEngine.shared.update(Atmosphere.shared.params, enabled: s.soundOn, intensity: s.intensity)
        if s.overlayOn {
            WindowTracker.shared.refresh()
            for p in pairs { p.sim.step(dt: dt) }
        }
        for p in pairs where p.overlay.isVisible != s.overlayOn {
            if s.overlayOn { p.overlay.orderFrontRegardless() } else { p.overlay.orderOut(nil) }
        }
    }

    private func rebuild() {
        for p in pairs { p.background.orderOut(nil); p.overlay.orderOut(nil) }
        pairs = NSScreen.screens.map { screen in
            let bg = makeWindow(screen: screen, level: Int(CGWindowLevelForKey(.desktopWindow)) + 1, opaque: true)
            // Metal が使えない環境では従来の Canvas 版にフォールバック
            bg.contentView = MetalLandscapeView(sceneFrame: CGRect(origin: .zero, size: screen.frame.size))
                ?? NSHostingView(rootView: LandscapeView())
            bg.orderFront(nil)

            let sim = OverlaySimulation(screen: screen)
            // Dock より上・クリックは透過
            let ov = makeWindow(screen: screen, level: Int(CGWindowLevelForKey(.dockWindow)) + 1, opaque: false)
            ov.contentView = NSHostingView(rootView: OverlayView(sim: sim))
            ov.orderFrontRegardless()
            return Pair(screen: screen, background: bg, overlay: ov, sim: sim)
        }
    }

    private func makeWindow(screen: NSScreen, level: Int, opaque: Bool) -> NSWindow {
        let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.setFrame(screen.frame, display: false)
        w.level = NSWindow.Level(rawValue: level)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        w.ignoresMouseEvents = true
        w.isOpaque = opaque
        w.backgroundColor = opaque ? .black : .clear
        w.hasShadow = false
        w.isReleasedWhenClosed = false
        return w
    }
}

import AppKit
import CoreGraphics

/// 他アプリのウィンドウ矩形を前面順に取得する（画面収録権限は不要。位置とサイズのみ使用）。
final class WindowTracker {
    static let shared = WindowTracker()

    struct Win {
        var id: CGWindowID
        var rect: CGRect   // グローバル座標（左上原点・メイン画面基準）
    }

    /// 前面 → 背面の順
    private(set) var windows: [Win] = []
    /// Dock らしきウィンドウ矩形（グローバル左上原点）
    private(set) var dockRects: [CGRect] = []
    private let myPID = ProcessInfo.processInfo.processIdentifier

    func refresh() {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }
        var wins: [Win] = []
        var docks: [CGRect] = []
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let num = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            let rect = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            let owner = info[kCGWindowOwnerName as String] as? String
            if owner == "Dock", layer == Int(CGWindowLevelForKey(.dockWindow)) {
                docks.append(rect)
                continue
            }
            if pid == myPID || layer != 0 { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.1 { continue }
            if rect.width < 80 || rect.height < 40 { continue }
            wins.append(Win(id: num, rect: rect))
        }
        windows = wins
        dockRects = docks
    }

    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// グローバル左上原点 → 画面ローカル左上原点
    static func toLocal(_ r: CGRect, screen: NSScreen) -> CGRect {
        let f = screen.frame
        let topY = primaryHeight - f.maxY
        return CGRect(x: r.minX - f.minX, y: r.minY - topY, width: r.width, height: r.height)
    }
}

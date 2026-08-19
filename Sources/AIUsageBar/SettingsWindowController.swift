import AppKit
import SwiftUI

/// Presents the settings view explicitly instead of relying on SwiftUI's
/// private `showSettingsWindow:` action. That action is not dependable for a
/// menu-bar accessory app whose dashboard is hosted in a non-activating panel.
@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = NSHostingController(
            rootView: AccountSettingsView()
        )
        window.title = "AI Usage Bar 设置"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 430)
        window.center()

        // The dashboard itself is a floating panel. Keep settings at the same
        // level so the window cannot open behind the dashboard.
        window.level = .floating

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("SettingsWindowController does not support NSCoder")
    }

    func show() {
        guard let window else { return }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

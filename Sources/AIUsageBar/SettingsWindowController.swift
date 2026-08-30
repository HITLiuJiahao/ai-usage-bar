import AppKit
import Combine
import SwiftUI

/// Presents the settings view explicitly instead of relying on SwiftUI's
/// private `showSettingsWindow:` action. That action is not dependable for a
/// menu-bar accessory app whose dashboard is hosted in a non-activating panel.
@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private var languageCancellable: AnyCancellable?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = NSHostingController(
            rootView: AccountSettingsView()
        )
        window.title = L10n.text(.settingsWindowTitle)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 560)
        window.center()

        // The dashboard itself is a floating panel. Keep settings at the same
        // level so the window cannot open behind the dashboard.
        window.level = .floating

        super.init(window: window)
        languageCancellable = AppLanguageSettings.shared.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.window?.title = L10n.text(.settingsWindowTitle)
            }
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

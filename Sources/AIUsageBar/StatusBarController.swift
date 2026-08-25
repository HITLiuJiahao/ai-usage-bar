import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, ObservableObject {
    private let store: UsageStore
    private let dashboardPanel = NSPanel(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: true
    )
    private let contextMenu = NSMenu()
    private var cancellables = Set<AnyCancellable>()
    private var statusItem: NSStatusItem?
    private var localOutsideClickMonitor: Any?
    private var globalOutsideClickMonitor: Any?
    private var isDashboardPanelConfigured = false

    init(store: UsageStore) {
        self.store = store
        super.init()
        configureStatusItem()
        configureContextMenu()
        store.$snapshots
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)
        updateStatusItem()

        // Creating an NSHostingController and resizing its NSPanel while a
        // SwiftUI App is still constructing its scene can abort AttributeGraph.
        // Wait until the app has entered the main run loop before attaching it.
        DispatchQueue.main.async { [weak self] in
            self?.configureDashboardPanel()
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        if let remaining = store.codexWeeklyRemainingPercent {
            button.image = CodexQuotaStatusImage.make(remainingPercent: remaining)
            button.title = "\(remaining)"
            button.imagePosition = .imageLeft
            button.imageScaling = .scaleProportionallyDown
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            button.toolTip = "Codex 周额度剩余 \(remaining)% · 点击查看 AI 使用概览"
        } else {
            button.image = NSImage(
                systemSymbolName: "gauge.medium",
                accessibilityDescription: "AI 使用概览"
            )
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = "AI 使用概览"
        }
    }

    private func configureDashboardPanel() {
        guard !isDashboardPanelConfigured else { return }

        dashboardPanel.contentViewController = NSHostingController(
            rootView: DashboardPopover(
                store: store,
                onSizeChange: { [weak self] size in
                    self?.updateDashboardSize(size)
                }
            )
        )

        dashboardPanel.isFloatingPanel = true
        // Keep the status item above the dashboard. Using .statusBar here can
        // cover the very button that opened the dashboard on small screens.
        dashboardPanel.level = .floating
        dashboardPanel.hidesOnDeactivate = false
        dashboardPanel.isOpaque = false
        dashboardPanel.backgroundColor = .clear
        dashboardPanel.hasShadow = true
        dashboardPanel.isMovable = false
        dashboardPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isDashboardPanelConfigured = true
    }

    private var dashboardScreenVisibleFrame: CGRect? {
        statusItem?.button?.window?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
    }

    private func updateDashboardSize(_ size: CGSize) {
        let contentSize = NSSize(width: size.width, height: size.height)
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.isDashboardPanelConfigured,
                  self.dashboardPanel.contentViewController != nil
            else { return }

            let currentSize = self.dashboardPanel.contentView?.frame.size ?? .zero
            let widthChanged = abs(currentSize.width - contentSize.width) > 0.5
            let heightChanged = abs(currentSize.height - contentSize.height) > 0.5
            if widthChanged || heightChanged {
                if self.dashboardPanel.isVisible {
                    self.positionDashboardPanel(contentSize: contentSize, animated: true)
                } else {
                    self.dashboardPanel.setContentSize(contentSize)
                }
            } else if self.dashboardPanel.isVisible {
                self.positionDashboardPanel()
            }
        }
    }

    private func positionDashboardPanel(
        contentSize: NSSize? = nil,
        animated: Bool = false
    ) {
        guard let screen = statusItem?.button?.window?.screen
                ?? NSScreen.main
                ?? NSScreen.screens.first
        else { return }

        let buttonScreenFrame: NSRect?
        if let button = statusItem?.button,
           let buttonWindow = button.window {
            buttonScreenFrame = buttonWindow.convertToScreen(
                button.convert(button.bounds, to: nil)
            )
        } else {
            buttonScreenFrame = nil
        }

        let safeFrame = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        var frame = dashboardPanel.frame
        if let contentSize {
            frame.size = contentSize
        }
        guard frame.width > 0, frame.height > 0 else { return }

        // Use the screen center instead of the status-item anchor. The old
        // anchor-based placement could push the restored wide canvas off the
        // left edge when the status item was near the right edge.
        let targetX = screen.visibleFrame.midX - frame.width / 2

        // Always open below the menu bar. Never move the panel above the
        // status item: that would put it over the menu bar and hide the icon.
        let targetY = (buttonScreenFrame?.minY ?? screen.visibleFrame.maxY)
            - frame.height - 6

        let maximumX = max(safeFrame.minX, safeFrame.maxX - frame.width)
        let maximumY = max(safeFrame.minY, safeFrame.maxY - frame.height)
        frame.origin.x = min(max(targetX, safeFrame.minX), maximumX)
        frame.origin.y = min(max(targetY, safeFrame.minY), maximumY)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                dashboardPanel.animator().setFrame(frame, display: true)
            }
        } else {
            dashboardPanel.setFrame(frame, display: true)
        }
    }

    private func configureContextMenu() {
        contextMenu.autoenablesItems = false

        let refresh = NSMenuItem(
            title: "刷新用量",
            action: #selector(refreshUsage),
            keyEquivalent: ""
        )
        refresh.target = self
        contextMenu.addItem(refresh)

        let settings = NSMenuItem(
            title: "账户设置…",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settings.target = self
        contextMenu.addItem(settings)

        contextMenu.addItem(.separator())

        let quit = NSMenuItem(
            title: "退出 AI Usage Bar",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quit.target = self
        contextMenu.addItem(quit)
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        switch event.type {
        case .rightMouseDown, .rightMouseUp:
            showContextMenu()
        default:
            togglePopover()
        }
    }

    private func togglePopover() {
        guard statusItem?.button != nil else { return }
        if !isDashboardPanelConfigured {
            configureDashboardPanel()
        }
        if dashboardPanel.isVisible {
            closeDashboard()
        } else {
            store.refresh()
            if dashboardPanel.contentView?.frame.size == .zero {
                let initialSize = DashboardLayout.fittingSize(
                    forModuleCount: 0,
                    visibleFrame: dashboardScreenVisibleFrame
                )
                dashboardPanel.setContentSize(
                    NSSize(width: initialSize.width, height: initialSize.height)
                )
            }
            positionDashboardPanel()
            dashboardPanel.orderFrontRegardless()
            dashboardPanel.makeKey()
            DispatchQueue.main.async { [weak self] in
                self?.positionDashboardPanel()
            }
            installOutsideClickMonitors()
        }
    }

    private func closeDashboard() {
        dashboardPanel.orderOut(nil)
        removeOutsideClickMonitors()
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()

        let clickEvents: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]

        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: clickEvents) {
            [weak self] event in
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                self?.closePopoverIfNeeded(at: location, eventWindow: event.window)
            }
            return event
        }

        globalOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clickEvents) {
            [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                self?.closePopoverIfNeeded(at: location, eventWindow: nil)
            }
        }
    }

    private func removeOutsideClickMonitors() {
        if let localOutsideClickMonitor {
            NSEvent.removeMonitor(localOutsideClickMonitor)
            self.localOutsideClickMonitor = nil
        }
        if let globalOutsideClickMonitor {
            NSEvent.removeMonitor(globalOutsideClickMonitor)
            self.globalOutsideClickMonitor = nil
        }
    }

    private func closePopoverIfNeeded(at location: NSPoint, eventWindow: NSWindow?) {
        guard dashboardPanel.isVisible else { return }
        guard !isInsidePopover(at: location, eventWindow: eventWindow) else { return }
        guard !isInsideStatusItem(at: location) else { return }
        closeDashboard()
    }

    private func isInsidePopover(at location: NSPoint, eventWindow: NSWindow?) -> Bool {
        if let eventWindow, eventWindow === dashboardPanel {
            return true
        }
        return dashboardPanel.frame.contains(location)
    }

    private func isInsideStatusItem(at location: NSPoint) -> Bool {
        guard let button = statusItem?.button,
              let window = button.window else { return false }
        let buttonFrame = button.convert(button.bounds, to: nil)
        return window.convertToScreen(buttonFrame).contains(location)
    }

    private func showContextMenu() {
        guard let button = statusItem?.button else { return }
        if dashboardPanel.isVisible {
            closeDashboard()
        }
        contextMenu.popUp(
            positioning: nil,
            at: NSPoint(x: button.bounds.midX, y: button.bounds.minY),
            in: button
        )
    }

    @objc private func refreshUsage() {
        store.refresh()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

}

private enum CodexQuotaStatusImage {
    static func make(remainingPercent: Int) -> NSImage {
        let size = NSSize(width: 15, height: 15)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - 2
        let track = NSBezierPath(
            ovalIn: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
        track.lineWidth = 2
        NSColor.white.withAlphaComponent(0.24).setStroke()
        track.stroke()

        let clamped = min(max(remainingPercent, 0), 100)
        guard clamped > 0 else { return image }

        let progress = NSBezierPath()
        progress.lineWidth = 2
        progress.lineCapStyle = .round
        progress.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - (360 * CGFloat(clamped) / 100),
            clockwise: true
        )
        NSColor.systemBlue.setStroke()
        progress.stroke()
        return image
    }
}

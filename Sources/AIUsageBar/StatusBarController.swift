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
    private let edgeDockPanel = NSPanel(
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
    private var edgeDockLocalMouseMonitor: Any?
    private var edgeDockGlobalMouseMonitor: Any?
    private var edgeDockHideTask: Task<Void, Never>?
    private var isDashboardPanelConfigured = false
    private var isEdgeDockConfigured = false
    private var isEdgeDockHiding = false

    init(store: UsageStore) {
        self.store = store
        super.init()
        AppUpdater.shared.startAutomaticChecks()
        configureStatusItem()
        configureContextMenu()
        store.$snapshots
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)
        AppLanguageSettings.shared.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.configureContextMenu()
                self?.updateStatusItem()
            }
            .store(in: &cancellables)
        updateStatusItem()

        // Creating an NSHostingController and resizing its NSPanel while a
        // SwiftUI App is still constructing its scene can abort AttributeGraph.
        // Wait until the app has entered the main run loop before attaching it.
        DispatchQueue.main.async { [weak self] in
            self?.configureDashboardPanel()
            self?.configureEdgeDockPanel()
        }

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.positionEdgeDockPanel()
                if self?.dashboardPanel.isVisible == true {
                    self?.positionDashboardPanel()
                }
            }
            .store(in: &cancellables)

        installEdgeDockMonitors()
    }

    deinit {
        edgeDockHideTask?.cancel()
        if let edgeDockLocalMouseMonitor {
            NSEvent.removeMonitor(edgeDockLocalMouseMonitor)
        }
        if let edgeDockGlobalMouseMonitor {
            NSEvent.removeMonitor(edgeDockGlobalMouseMonitor)
        }
        if let localOutsideClickMonitor {
            NSEvent.removeMonitor(localOutsideClickMonitor)
        }
        if let globalOutsideClickMonitor {
            NSEvent.removeMonitor(globalOutsideClickMonitor)
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
        let statusQuota = store.codexStatusQuota
        if let statusQuota {
            let remaining = statusQuota.remaining
            button.image = CodexQuotaStatusImage.make(remainingPercent: remaining)
            button.attributedTitle = NSAttributedString(
                string: "\(remaining)%",
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: NSColor.white
                ]
            )
            button.imagePosition = .imageLeft
            button.imageScaling = .scaleProportionallyDown
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            button.toolTip = L10n.codexStatusTooltip(
                remaining: remaining,
                window: statusQuota.window
            )
        } else {
            button.image = NSImage(
                systemSymbolName: "gauge.medium",
                accessibilityDescription: L10n.text(.overviewTitle)
            )
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
            button.toolTip = L10n.text(.overviewTitle)
        }
    }

    private func configureDashboardPanel() {
        guard !isDashboardPanelConfigured else { return }

        dashboardPanel.contentViewController = NSHostingController(
            rootView: DashboardPopover(
                store: store,
                visibleFrame: dashboardScreenVisibleFrame,
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

    private func configureEdgeDockPanel() {
        guard !isEdgeDockConfigured else { return }

        edgeDockPanel.contentViewController = NSHostingController(
            rootView: EdgeDockView(
                store: store,
                onSizeChange: { [weak self] size in
                    self?.updateEdgeDockSize(size)
                },
                onOpenDashboard: { [weak self] in
                    self?.showDashboard()
                }
            )
        )

        edgeDockPanel.isFloatingPanel = true
        edgeDockPanel.level = .floating
        edgeDockPanel.hidesOnDeactivate = false
        edgeDockPanel.isOpaque = false
        edgeDockPanel.backgroundColor = .clear
        edgeDockPanel.hasShadow = false
        edgeDockPanel.isMovable = false
        edgeDockPanel.becomesKeyOnlyIfNeeded = true
        edgeDockPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        edgeDockPanel.setContentSize(
            NSSize(width: EdgeDockLayout.collapsedWidth, height: EdgeDockLayout.panelHeight)
        )
        isEdgeDockConfigured = true

        positionEdgeDockPanel()
    }

    private var dashboardScreenVisibleFrame: CGRect? {
        statusItem?.button?.window?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
    }

    private func updateDashboardSize(_ size: CGSize) {
        let contentSize = constrainedDashboardSize(
            NSSize(width: size.width, height: size.height)
        )
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

    private func updateEdgeDockSize(_ size: CGSize) {
        let contentSize = NSSize(width: size.width, height: size.height)
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.isEdgeDockConfigured,
                  self.edgeDockPanel.contentViewController != nil
            else { return }

            let currentSize = self.edgeDockPanel.contentView?.frame.size ?? .zero
            let widthChanged = abs(currentSize.width - contentSize.width) > 0.5
            let heightChanged = abs(currentSize.height - contentSize.height) > 0.5
            if widthChanged || heightChanged {
                self.positionEdgeDockPanel(
                    contentSize: contentSize,
                    animated: self.edgeDockPanel.isVisible
                )
            } else if self.edgeDockPanel.isVisible {
                self.positionEdgeDockPanel()
            }
        }
    }

    private var edgeDockScreen: NSScreen? {
        statusItem?.button?.window?.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func positionEdgeDockPanel(
        contentSize: NSSize? = nil,
        animated: Bool = false
    ) {
        guard let screen = edgeDockScreen else { return }

        let frame = edgeDockFrame(contentSize: contentSize, on: screen)
        guard frame.width > 0, frame.height > 0 else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                edgeDockPanel.animator().setFrame(frame, display: true)
            }
        } else {
            edgeDockPanel.setFrame(frame, display: true)
        }
    }

    private func installEdgeDockMonitors() {
        removeEdgeDockMonitors()

        let events: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]

        edgeDockLocalMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) {
            [weak self] event in
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                self?.handleEdgeDockPointer(event.type, at: location)
            }
            return event
        }

        edgeDockGlobalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) {
            [weak self] event in
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                self?.handleEdgeDockPointer(event.type, at: location)
            }
        }
    }

    private func removeEdgeDockMonitors() {
        if let edgeDockLocalMouseMonitor {
            NSEvent.removeMonitor(edgeDockLocalMouseMonitor)
            self.edgeDockLocalMouseMonitor = nil
        }
        if let edgeDockGlobalMouseMonitor {
            NSEvent.removeMonitor(edgeDockGlobalMouseMonitor)
            self.edgeDockGlobalMouseMonitor = nil
        }
    }

    private func handleEdgeDockPointer(_ eventType: NSEvent.EventType, at location: NSPoint) {
        if eventType == .mouseMoved {
            if isInsideEdgeTrigger(at: location) {
                showEdgeDockPanel(on: screen(containing: location))
            } else if edgeDockPanel.isVisible {
                if isInsideEdgeDock(at: location) {
                    cancelEdgeDockHide()
                } else {
                    scheduleEdgeDockHide()
                }
            } else if isInsideEdgeTrigger(at: location) {
                showEdgeDockPanel()
            }
            return
        }

        guard edgeDockPanel.isVisible, !isInsideEdgeDock(at: location) else { return }
        hideEdgeDockPanel(animated: true)
    }

    private func isInsideEdgeTrigger(at location: NSPoint) -> Bool {
        guard let screen = screen(containing: location) else { return false }
        let frame = screen.visibleFrame
        return location.x >= frame.maxX - 5
            && location.y >= frame.minY
            && location.y <= frame.maxY
    }

    private func screen(containing location: NSPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(location) }) ?? edgeDockScreen
    }

    private func isInsideEdgeDock(at location: NSPoint) -> Bool {
        edgeDockPanel.frame.insetBy(dx: -6, dy: -6).contains(location)
    }

    private func cancelEdgeDockHide() {
        edgeDockHideTask?.cancel()
        edgeDockHideTask = nil
    }

    private func scheduleEdgeDockHide() {
        guard edgeDockPanel.isVisible else { return }
        edgeDockHideTask?.cancel()
        edgeDockHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled, let self else { return }
            let location = NSEvent.mouseLocation
            guard !self.isInsideEdgeDock(at: location) else { return }
            self.hideEdgeDockPanel(animated: true)
        }
    }

    private func showEdgeDockPanel(on screen: NSScreen? = nil) {
        cancelEdgeDockHide()
        if !isEdgeDockConfigured {
            configureEdgeDockPanel()
        }
        guard let screen = screen ?? edgeDockScreen else { return }

        let wasHiding = isEdgeDockHiding
        guard !edgeDockPanel.isVisible || wasHiding else { return }
        isEdgeDockHiding = false

        let targetFrame = edgeDockFrame(
            contentSize: edgeDockPanel.frame.size,
            on: screen
        )
        if !edgeDockPanel.isVisible {
            var startingFrame = targetFrame
        startingFrame.origin.x = screen.visibleFrame.maxX + EdgeDockLayout.edgeOverlap + 4
            edgeDockPanel.setFrame(startingFrame, display: false)
        }
        edgeDockPanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            edgeDockPanel.animator().setFrame(targetFrame, display: true)
        }
    }

    private func hideEdgeDockPanel(animated: Bool) {
        cancelEdgeDockHide()
        guard edgeDockPanel.isVisible, !isEdgeDockHiding else { return }

        guard animated, let screen = edgeDockScreen else {
            isEdgeDockHiding = false
            edgeDockPanel.orderOut(nil)
            edgeDockPanel.contentViewController = nil
            isEdgeDockConfigured = false
            return
        }

        isEdgeDockHiding = true
        var endingFrame = edgeDockPanel.frame
        endingFrame.origin.x = screen.visibleFrame.maxX + EdgeDockLayout.edgeOverlap + 4
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            edgeDockPanel.animator().setFrame(endingFrame, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isEdgeDockHiding else { return }
                self.isEdgeDockHiding = false
                self.edgeDockPanel.orderOut(nil)
                self.edgeDockPanel.contentViewController = nil
                self.isEdgeDockConfigured = false
            }
        })
    }

    private func edgeDockFrame(contentSize: NSSize?, on screen: NSScreen) -> NSRect {
        var frame = edgeDockPanel.frame
        if let contentSize, contentSize.width > 0, contentSize.height > 0 {
            frame.size = contentSize
        }
        let visibleFrame = screen.visibleFrame
        let verticalInset: CGFloat = 8
        let minimumY = visibleFrame.minY + verticalInset
        let maximumY = max(minimumY, visibleFrame.maxY - verticalInset - frame.height)
        let centeredY = visibleFrame.midY - frame.height / 2
        frame.origin.x = visibleFrame.maxX - frame.width + EdgeDockLayout.edgeOverlap
        frame.origin.y = min(max(centeredY, minimumY), maximumY)
        return frame
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
            frame.size = constrainedDashboardSize(contentSize, on: screen)
        } else {
            frame.size = constrainedDashboardSize(frame.size, on: screen)
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
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                dashboardPanel.animator().setFrame(frame, display: true)
            }
        } else {
            dashboardPanel.setFrame(frame, display: true)
        }
    }

    private func constrainedDashboardSize(_ size: NSSize, on screen: NSScreen? = nil) -> NSSize {
        guard size.width > 0, size.height > 0 else { return size }
        let targetScreen = screen ?? statusItem?.button?.window?.screen ?? NSScreen.main
        let visibleFrame = targetScreen?.visibleFrame
        let maximumHeight = DashboardLayout.maximumHeight(for: visibleFrame)
        return NSSize(
            width: size.width,
            height: min(size.height, maximumHeight)
        )
    }

    private func configureContextMenu() {
        contextMenu.autoenablesItems = false
        contextMenu.removeAllItems()

        let refresh = NSMenuItem(
            title: L10n.text(.menuRefresh),
            action: #selector(refreshUsage),
            keyEquivalent: ""
        )
        refresh.target = self
        contextMenu.addItem(refresh)

        let dashboard = NSMenuItem(
            title: L10n.text(.menuDashboard),
            action: #selector(openDashboardFromMenu),
            keyEquivalent: ""
        )
        dashboard.target = self
        contextMenu.addItem(dashboard)

        let settings = NSMenuItem(
            title: L10n.text(.menuSettings),
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settings.target = self
        contextMenu.addItem(settings)

        contextMenu.addItem(.separator())

        let quit = NSMenuItem(
            title: L10n.text(.menuQuit),
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quit.target = self
        contextMenu.addItem(quit)
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            toggleEdgeDock()
            return
        }

        switch event.type {
        case .rightMouseDown, .rightMouseUp:
            showContextMenu()
        default:
            toggleEdgeDock()
        }
    }

    private func toggleEdgeDock() {
        if edgeDockPanel.isVisible, !isEdgeDockHiding {
            hideEdgeDockPanel(animated: true)
        } else {
            if dashboardPanel.isVisible {
                closeDashboard()
            }
            showEdgeDockPanel()
        }
    }

    private func showDashboard() {
        guard statusItem?.button != nil else { return }
        hideEdgeDockPanel(animated: true)
        if !isDashboardPanelConfigured {
            configureDashboardPanel()
        }
        store.refresh(forceQuota: true)
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
        store.refresh(forceQuota: true)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func openDashboardFromMenu() {
        showDashboard()
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

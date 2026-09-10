import AppKit
import Combine
import QuartzCore
import SwiftUI

/// Owns the actual desktop-pet panel. It deliberately stays separate from the
/// edge dock so the pet can be moved freely and remains visible across Spaces.
@MainActor
final class DesktopPetWindowController: NSObject {
    static let shared = DesktopPetWindowController(store: .shared)

    private static let positionKey = "aiUsageBar.desktopPet.position"

    private let store: DesktopPetStore
    private var panel: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var rightClickMonitor: Any?
    private var screenObserver: Any?
    private var hideReminderObserver: Any?
    private var statsPopover: NSPopover?
    private var hotKeyController: DesktopPetHotKeyController?
    /// Native mouse tracking deliberately keeps the drag path out of SwiftUI's
    /// animation/layout pipeline.  That makes the floating panel follow the
    /// pointer even while a provider snapshot or pet mood changes underneath it.
    private var dragState: PetDragState?
    private var didStart = false
    private var isShowingHideReminder = false

    private init(store: DesktopPetStore) {
        self.store = store
        super.init()
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        createPanelIfNeeded()
        store.$preferences
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyPreferences()
            }
            .store(in: &cancellables)
        AppLanguageSettings.shared.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshHostingView()
            }
            .store(in: &cancellables)

        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            self.showHUD()
            return nil
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.ensurePanelIsVisible()
            }
        }
        hideReminderObserver = NotificationCenter.default.addObserver(
            forName: .aiUsageBarDesktopPetDidHide,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.showHideReminderIfNeeded()
            }
        }
        hotKeyController = DesktopPetHotKeyController { [weak self] action in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch action {
                case .show:
                    self.showPet()
                case .hide:
                    guard self.store.preferences.isEnabled else { return }
                    self.hidePet()
                }
            }
        }
        store.$showPetShortcut
            .combineLatest(store.$hidePetShortcut)
            .receive(on: RunLoop.main)
            .sink { [weak self] show, hide in
                self?.hotKeyController?.update(show: show, hide: hide)
            }
            .store(in: &cancellables)
        applyPreferences()
    }

    deinit {
        if let rightClickMonitor { NSEvent.removeMonitor(rightClickMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let hideReminderObserver { NotificationCenter.default.removeObserver(hideReminderObserver) }
        hotKeyController = nil
    }

    func showPet() {
        createPanelIfNeeded()
        store.setEnabled(true)
        panel?.orderFrontRegardless()
    }

    func hidePet() {
        store.setEnabled(false)
    }

    func showHUDFromSettings() {
        createPanelIfNeeded()
        store.setEnabled(true)
        showHUD()
    }

    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: Self.positionKey)
        guard let panel else { return }
        let origin = defaultOrigin(for: panel.frame.size)
        panel.setFrameOrigin(origin)
    }

    func beginDrag(at pointer: NSPoint) {
        guard let panel else { return }
        dragState = PetDragState(
            panelOrigin: panel.frame.origin,
            pointerOrigin: pointer
        )
    }

    func updateDrag(to pointer: NSPoint) {
        guard let panel, let dragState else { return }
        let frame = panel.frame
        let target = NSPoint(
            x: dragState.panelOrigin.x + pointer.x - dragState.pointerOrigin.x,
            y: dragState.panelOrigin.y + pointer.y - dragState.pointerOrigin.y
        )
        let bounded = clampedOrigin(target, size: frame.size)
        setPanelOriginImmediately(bounded)
    }

    func endDrag() {
        guard let panel else { return }
        let origin = panel.frame.origin
        UserDefaults.standard.set([Double(origin.x), Double(origin.y)], forKey: Self.positionKey)
        dragState = nil
    }

    private func createPanelIfNeeded() {
        guard panel == nil else { return }
        let size = desiredSize
        let created = NSPanel(
            contentRect: NSRect(origin: defaultOrigin(for: size), size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        created.level = .floating
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = false
        created.isMovableByWindowBackground = false
        created.becomesKeyOnlyIfNeeded = true
        created.hidesOnDeactivate = false
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        created.contentView = NSHostingView(
            rootView: DesktopPetFloatingView(store: store, onShowHUD: { [weak self] in
                self?.showHUD()
            })
        )
        panel = created
        if let saved = savedOrigin() {
            created.setFrameOrigin(clampedOrigin(saved, size: size))
        }
    }

    private func refreshHostingView() {
        guard let panel else { return }
        panel.contentView = NSHostingView(
            rootView: DesktopPetFloatingView(store: store, onShowHUD: { [weak self] in
                self?.showHUD()
            })
        )
    }

    private func applyPreferences() {
        createPanelIfNeeded()
        guard let panel else { return }
        resizePanelIfNeeded()
        if store.preferences.isEnabled {
            panel.orderFrontRegardless()
        } else {
            statsPopover?.performClose(nil)
            panel.orderOut(nil)
        }
    }

    private var desiredSize: NSSize {
        let petSize = CGFloat(store.preferences.petSize)
        return NSSize(width: max(236, petSize + 78), height: petSize + 122)
    }

    private func resizePanelIfNeeded() {
        guard let panel else { return }
        let targetSize = desiredSize
        guard abs(panel.frame.width - targetSize.width) > 0.5 || abs(panel.frame.height - targetSize.height) > 0.5 else { return }
        let current = panel.frame
        let targetOrigin = clampedOrigin(
            NSPoint(
                x: current.midX - targetSize.width / 2,
                y: current.minY
            ),
            size: targetSize
        )
        panel.setFrame(NSRect(origin: targetOrigin, size: targetSize), display: true)
    }

    private func showHUD() {
        createPanelIfNeeded()
        guard let panel, let contentView = panel.contentView else { return }
        if let existing = statsPopover, existing.isShown {
            existing.performClose(nil)
            return
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: DesktopPetHUDView(store: store) {
                popover.performClose(nil)
                SettingsWindowController.shared.show()
            }
        )
        statsPopover = popover
        popover.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .maxY)
        panel.orderFrontRegardless()
    }

    private func showHideReminderIfNeeded() {
        guard store.shouldShowHideReminder, !isShowingHideReminder else { return }
        isShowingHideReminder = true
        defer { isShowingHideReminder = false }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = PetUI.text("桌面宠物已关闭", "Desktop Pet Hidden")
        alert.informativeText = PetUI.text(
            "按 \(store.showPetShortcut.displayName) 可立即重新开启；也可以右键点击菜单栏中的 AI Usage Bar 图标，选择“显示桌面宠物”，或在设置中打开。",
            "Press \(store.showPetShortcut.displayName) to show it again, or right-click the AI Usage Bar icon and choose “Show Desktop Pet”; you can also enable it in Settings."
        )
        let acknowledgeButton = alert.addButton(withTitle: PetUI.text("知道了", "OK"))
        acknowledgeButton.keyEquivalent = "\r"
        alert.addButton(withTitle: PetUI.text("立即开启", "Show Now"))
        alert.addButton(withTitle: PetUI.text("不再提示", "Don't Remind Me Again"))

        switch alert.runModal() {
        case .alertSecondButtonReturn:
            showPet()
        case .alertThirdButtonReturn:
            store.suppressHideReminder()
        default:
            break
        }
    }

    private func savedOrigin() -> NSPoint? {
        guard let coordinates = UserDefaults.standard.array(forKey: Self.positionKey) as? [Double],
              coordinates.count == 2
        else { return nil }
        return NSPoint(x: coordinates[0], y: coordinates[1])
    }

    private func defaultOrigin(for size: NSSize) -> NSPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        return NSPoint(
            x: frame.maxX - size.width - 28,
            y: frame.minY + 70
        )
    }

    private func ensurePanelIsVisible() {
        guard let panel else { return }
        panel.setFrameOrigin(clampedOrigin(panel.frame.origin, size: panel.frame.size))
    }

    /// NSPanel does not normally animate frame moves, but an active layer
    /// transaction from a SwiftUI update can make a drag look one frame behind.
    /// Disable only the window-frame transaction; sprite and bubble animations
    /// remain untouched in their SwiftUI hierarchy.
    private func setPanelOriginImmediately(_ origin: NSPoint) {
        guard let panel else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.setFrameOrigin(origin)
        CATransaction.commit()
    }

    private func clampedOrigin(_ origin: NSPoint, size: NSSize) -> NSPoint {
        let candidate = NSRect(origin: origin, size: size)
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(candidate) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return origin }
        let maxX = max(visible.minX, visible.maxX - size.width)
        let maxY = max(visible.minY, visible.maxY - size.height)
        return NSPoint(
            x: min(max(origin.x, visible.minX), maxX),
            y: min(max(origin.y, visible.minY), maxY)
        )
    }
}

private struct PetDragState {
    let panelOrigin: NSPoint
    let pointerOrigin: NSPoint
}

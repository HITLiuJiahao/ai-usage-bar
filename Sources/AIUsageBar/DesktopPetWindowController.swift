import AppKit
import Combine
import CoreGraphics
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
    private var sessionActiveObserver: Any?
    private var sessionInactiveObserver: Any?
    private var ownerGreetingTimer: Timer?
    private var ownerSessionActive = true
    private var statsPopover: NSPopover?
    private var hotKeyController: DesktopPetHotKeyController?
    private var petAnimationTask: Task<Void, Never>?
    private var petAnimationGeneration = 0
    private var animationHomeOrigin: NSPoint?
    private var didResolveInitialVisibility = false
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
        store.$activeSessions
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.resizePanelIfNeeded()
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
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        sessionActiveObserver = workspaceNotifications.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.ownerSessionActive = true
                self?.greetOwnerIfPresent()
            }
        }
        sessionInactiveObserver = workspaceNotifications.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.ownerSessionActive = false
            }
        }
        let greetingTimer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.greetOwnerIfPresent()
            }
        }
        greetingTimer.tolerance = 5
        RunLoop.main.add(greetingTimer, forMode: .common)
        ownerGreetingTimer = greetingTimer
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
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        if let sessionActiveObserver { workspaceNotifications.removeObserver(sessionActiveObserver) }
        if let sessionInactiveObserver { workspaceNotifications.removeObserver(sessionInactiveObserver) }
        ownerGreetingTimer?.invalidate()
        hotKeyController = nil
    }

    func showPet() {
        createPanelIfNeeded()
        guard let panel else { return }
        let wasVisible = panel.isVisible
        let wasAnimating = store.animationPhase != .idle
        let restingOrigin = animationHomeOrigin ?? panel.frame.origin
        cancelPetAnimation()
        store.setEnabled(true)

        if !wasVisible {
            beginPetEntrance(panel, restingOrigin: restingOrigin)
        } else if wasAnimating {
            recoverPetToRestingPosition(panel, restingOrigin: restingOrigin)
        } else {
            panel.orderFrontRegardless()
            greetOwnerIfPresent()
        }
    }

    func setPetEnabledFromSettings(_ enabled: Bool) {
        if enabled {
            showPet()
        } else {
            hidePet()
        }
    }

    func hidePet() {
        guard store.preferences.isEnabled,
              let panel,
              panel.isVisible,
              !store.animationPhase.isLeaving
        else { return }

        let shouldWave = store.animationPhase == .idle
        let restingOrigin = animationHomeOrigin ?? panel.frame.origin
        cancelPetAnimation()
        animationHomeOrigin = restingOrigin
        statsPopover?.performClose(nil)

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            store.setAnimationPhase(.fadingOut)
            let generation = petAnimationGeneration
            petAnimationTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 180_000_000)
                } catch {
                    return
                }
                guard let self, self.petAnimationGeneration == generation, !Task.isCancelled else { return }
                self.finishHidingPet(restingOrigin: restingOrigin)
            }
            return
        }

        let route = animationRoute(for: panel, restingOrigin: restingOrigin)
        let travelDuration = petTravelDuration(from: restingOrigin, to: route.offscreenOrigin, entering: false)
        if shouldWave {
            store.setAnimationPhase(.waving)
        }
        let generation = petAnimationGeneration
        petAnimationTask = Task { @MainActor [weak self] in
            if shouldWave {
                do {
                    try await Task.sleep(nanoseconds: 320_000_000)
                } catch {
                    return
                }
            }
            guard let self,
                  self.petAnimationGeneration == generation,
                  !Task.isCancelled,
                  self.store.preferences.isEnabled
            else { return }
            self.store.setAnimationPhase(.running(route.edge))
            self.animatePanel(
                to: route.offscreenOrigin,
                duration: travelDuration,
                timingFunction: .easeIn
            )

            do {
                try await Task.sleep(nanoseconds: UInt64(travelDuration * 1_000_000_000))
            } catch {
                return
            }
            guard self.petAnimationGeneration == generation,
                  !Task.isCancelled,
                  self.store.preferences.isEnabled
            else { return }
            self.finishHidingPet(restingOrigin: restingOrigin)
        }
    }

    func showHUDFromSettings() {
        showPet()
        showHUD()
    }

    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: Self.positionKey)
        guard let panel else { return }
        let origin = defaultOrigin(for: panel.frame.size)
        animationHomeOrigin = nil
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
        animationHomeOrigin = nil
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
            rootView: DesktopPetFloatingView(
                store: store,
                onShowHUD: { [weak self] in self?.showHUD() },
                onHidePet: { [weak self] in self?.hidePet() }
            )
        )
        panel = created
        if let saved = savedOrigin() {
            created.setFrameOrigin(clampedOrigin(saved, size: size))
        }
    }

    private func refreshHostingView() {
        guard let panel else { return }
        panel.contentView = NSHostingView(
            rootView: DesktopPetFloatingView(
                store: store,
                onShowHUD: { [weak self] in self?.showHUD() },
                onHidePet: { [weak self] in self?.hidePet() }
            )
        )
    }

    private func applyPreferences() {
        createPanelIfNeeded()
        guard let panel else { return }
        resizePanelIfNeeded()

        if !didResolveInitialVisibility {
            didResolveInitialVisibility = true
            if store.preferences.isEnabled {
                beginPetEntrance(panel, restingOrigin: panel.frame.origin)
            } else {
                panel.orderOut(nil)
            }
            return
        }

        if store.preferences.isEnabled {
            if panel.isVisible {
                panel.orderFrontRegardless()
                greetOwnerIfPresent()
            } else {
                beginPetEntrance(panel, restingOrigin: panel.frame.origin)
            }
        } else {
            statsPopover?.performClose(nil)
            panel.orderOut(nil)
        }
    }

    private func beginPetEntrance(_ panel: NSPanel, restingOrigin: NSPoint) {
        cancelPetAnimation()
        animationHomeOrigin = restingOrigin
        let route = animationRoute(for: panel, restingOrigin: restingOrigin)

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            setPanelOriginImmediately(restingOrigin)
            store.setAnimationPhase(.fadingIn)
            panel.orderFrontRegardless()
            let generation = petAnimationGeneration
            petAnimationTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 180_000_000)
                } catch {
                    return
                }
                guard let self, self.petAnimationGeneration == generation, !Task.isCancelled else { return }
                self.store.setAnimationPhase(.idle)
                self.animationHomeOrigin = nil
                self.petAnimationTask = nil
                self.resizePanelIfNeeded()
                self.greetOwnerIfPresent()
            }
            return
        }

        // Enter from the closest edge, then settle exactly where the user
        // placed the pet. The reverse path is used when it leaves.
        setPanelOriginImmediately(route.offscreenOrigin)
        store.setAnimationPhase(.arriving(route.edge))
        panel.orderFrontRegardless()
        let travelDuration = petTravelDuration(from: route.offscreenOrigin, to: restingOrigin, entering: true)
        animatePanel(to: restingOrigin, duration: travelDuration, timingFunction: .easeOut)

        let generation = petAnimationGeneration
        petAnimationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(travelDuration * 1_000_000_000))
            } catch {
                return
            }
            guard let self, self.petAnimationGeneration == generation, !Task.isCancelled else { return }
            self.setPanelOriginImmediately(restingOrigin)
            self.store.setAnimationPhase(.landing)

            do {
                try await Task.sleep(nanoseconds: 260_000_000)
            } catch {
                return
            }
            guard self.petAnimationGeneration == generation, !Task.isCancelled else { return }
            self.store.setAnimationPhase(.idle)
            self.animationHomeOrigin = nil
            self.petAnimationTask = nil
            self.resizePanelIfNeeded()
            self.greetOwnerIfPresent()
        }
    }

    private static let anyInputEventType = CGEventType(rawValue: UInt32.max)!

    private func greetOwnerIfPresent() {
        guard ownerSessionActive,
              store.preferences.isEnabled,
              store.preferences.showMessages,
              store.ownerGreeting == nil,
              panel?.isVisible == true,
              store.animationPhase == .idle
        else { return }
        let idleSeconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: Self.anyInputEventType
        )
        guard idleSeconds.isFinite, idleSeconds >= 0, idleSeconds <= 120 else { return }
        store.greetOwnerIfNeeded()
    }

    private func recoverPetToRestingPosition(_ panel: NSPanel, restingOrigin: NSPoint) {
        animationHomeOrigin = restingOrigin
        store.setAnimationPhase(.recovering)
        panel.orderFrontRegardless()

        let duration: TimeInterval = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.18 : 0.36
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            setPanelOriginImmediately(restingOrigin)
        } else {
            animatePanel(to: restingOrigin, duration: duration, timingFunction: .easeOut)
        }

        let generation = petAnimationGeneration
        petAnimationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            } catch {
                return
            }
            guard let self, self.petAnimationGeneration == generation, !Task.isCancelled else { return }
            self.setPanelOriginImmediately(restingOrigin)
            self.store.setAnimationPhase(.idle)
            self.animationHomeOrigin = nil
            self.petAnimationTask = nil
            self.resizePanelIfNeeded()
            self.greetOwnerIfPresent()
        }
    }

    private func finishHidingPet(restingOrigin: NSPoint) {
        panel?.orderOut(nil)
        setPanelOriginImmediately(restingOrigin)
        animationHomeOrigin = nil
        petAnimationTask = nil
        store.setEnabled(false)
        store.setAnimationPhase(.idle)
    }

    private func cancelPetAnimation() {
        petAnimationGeneration &+= 1
        petAnimationTask?.cancel()
        petAnimationTask = nil
    }

    private func animatePanel(
        to origin: NSPoint,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunctionName
    ) {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: timingFunction)
            context.allowsImplicitAnimation = true
            panel.animator().setFrameOrigin(origin)
        }
    }

    private func animationRoute(for panel: NSPanel, restingOrigin: NSPoint) -> PetAnimationRoute {
        let restingFrame = NSRect(origin: restingOrigin, size: panel.frame.size)
        let screen = NSScreen.screens.max { lhs, rhs in
            intersectionArea(lhs.visibleFrame, restingFrame) < intersectionArea(rhs.visibleFrame, restingFrame)
        } ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let petSize = CGFloat(store.preferences.petSize)
        let petCenterInPanel = NSPoint(x: restingFrame.width / 2, y: 8 + petSize / 2)
        let petCenter = NSPoint(
            x: restingFrame.minX + petCenterInPanel.x,
            y: restingFrame.minY + petCenterInPanel.y
        )
        let edge = [
            (DesktopPetScreenEdge.left, abs(petCenter.x - visibleFrame.minX)),
            (DesktopPetScreenEdge.right, abs(visibleFrame.maxX - petCenter.x)),
            (DesktopPetScreenEdge.top, abs(visibleFrame.maxY - petCenter.y)),
            (DesktopPetScreenEdge.bottom, abs(petCenter.y - visibleFrame.minY))
        ].min { $0.1 < $1.1 }?.0 ?? .right

        let clearance = petSize * 0.68 + 20
        var offscreenOrigin = restingOrigin
        switch edge {
        case .left:
            offscreenOrigin.x = visibleFrame.minX - petCenterInPanel.x - clearance
        case .right:
            offscreenOrigin.x = visibleFrame.maxX - petCenterInPanel.x + clearance
        case .top:
            offscreenOrigin.y = visibleFrame.maxY - petCenterInPanel.y + clearance
        case .bottom:
            offscreenOrigin.y = visibleFrame.minY - petCenterInPanel.y - clearance
        }
        return PetAnimationRoute(edge: edge, offscreenOrigin: offscreenOrigin)
    }

    private func petTravelDuration(from start: NSPoint, to end: NSPoint, entering: Bool) -> TimeInterval {
        let distance = Double(hypot(end.x - start.x, end.y - start.y))
        if entering {
            return min(0.72, max(0.42, 0.33 + distance / 950))
        }
        return min(0.64, max(0.32, 0.24 + distance / 1_250))
    }

    private func intersectionArea(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private var desiredSize: NSSize {
        let petSize = CGFloat(store.preferences.petSize)
        let activityBubbleHeight: CGFloat
        let sessionCount = store.activeSessions.count
        if store.preferences.showMessages, sessionCount > 0 {
            let contentHeight = min(
                PetAgentBubbleLayout.contentHeight(sessionCount: sessionCount),
                PetAgentBubbleLayout.maximumContentHeight(for: petSize)
            )
            activityBubbleHeight = contentHeight + 20
        } else {
            activityBubbleHeight = 0
        }

        // The bubble is positioned above the pet inside this panel. Grow the
        // panel upward as the bubble gains rows so AppKit does not clip its top.
        let requiredBubbleSpace = activityBubbleHeight > 0 ? activityBubbleHeight + 24 : 122
        return NSSize(
            width: max(236, petSize + 78),
            height: petSize + max(122, requiredBubbleSpace)
        )
    }

    private func resizePanelIfNeeded() {
        guard let panel else { return }
        // A session update must not clamp the panel back onscreen while the
        // pet is crossing the edge. Resize once it has reached its resting spot.
        guard animationHomeOrigin == nil else { return }
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
            rootView: DesktopPetHUDView(
                store: store,
                onOpenSettings: {
                    popover.performClose(nil)
                    SettingsWindowController.shared.show()
                },
                onHidePet: { [weak self] in self?.hidePet() }
            )
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

private struct PetAnimationRoute {
    let edge: DesktopPetScreenEdge
    let offscreenOrigin: NSPoint
}

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A global shortcut uses a small, stable modifier bitmask instead of storing
/// NSEvent's platform-specific raw values. This keeps the setting portable
/// across app launches while Carbon receives the modifier values it expects.
struct PetShortcut: Codable, Equatable, Hashable {
    static let commandModifier: UInt32 = 1 << 0
    static let optionModifier: UInt32 = 1 << 1
    static let controlModifier: UInt32 = 1 << 2
    static let shiftModifier: UInt32 = 1 << 3

    static let defaultShow = PetShortcut(
        keyCode: 35, // P
        modifiers: commandModifier | optionModifier
    )
    static let defaultHide = PetShortcut(
        keyCode: 35, // P
        modifiers: commandModifier | optionModifier | shiftModifier
    )

    var keyCode: UInt16
    var modifiers: UInt32

    var isValid: Bool {
        !Self.modifierKeyCodes.contains(keyCode) && modifiers != 0
    }

    var displayName: String {
        var result = ""
        if modifiers & Self.controlModifier != 0 { result += "⌃" }
        if modifiers & Self.optionModifier != 0 { result += "⌥" }
        if modifiers & Self.shiftModifier != 0 { result += "⇧" }
        if modifiers & Self.commandModifier != 0 { result += "⌘" }
        return result + Self.keyName(for: keyCode)
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers & Self.commandModifier != 0 { result |= UInt32(cmdKey) }
        if modifiers & Self.optionModifier != 0 { result |= UInt32(optionKey) }
        if modifiers & Self.controlModifier != 0 { result |= UInt32(controlKey) }
        if modifiers & Self.shiftModifier != 0 { result |= UInt32(shiftKey) }
        return result
    }

    static func from(_ event: NSEvent) -> PetShortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= commandModifier }
        if flags.contains(.option) { modifiers |= optionModifier }
        if flags.contains(.control) { modifiers |= controlModifier }
        if flags.contains(.shift) { modifiers |= shiftModifier }
        let shortcut = PetShortcut(keyCode: event.keyCode, modifiers: modifiers)
        return shortcut.isValid ? shortcut : nil
    }

    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    private static func keyName(for keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G",
            6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
            13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
            24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
            36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
            42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
            48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "⎋",
            71: "Clear", 75: "/", 76: "↩", 77: "=", 78: "0", 79: "1",
            80: "2", 81: "3", 82: "4", 83: "5", 84: "6", 85: "7",
            86: "8", 87: "9", 88: ".", 89: "+", 91: "F1", 92: "F2",
            93: "F3", 94: "F4", 95: "F5", 96: "F6", 97: "F7", 98: "F8",
            99: "F9", 100: "F10", 101: "F11", 109: "F12"
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}

enum DesktopPetHotKeyAction {
    case show
    case hide
}

/// Registers true system-wide shortcuts through Carbon. Unlike a global
/// NSEvent monitor, this does not require Accessibility permission and keeps
/// working while another app is focused.
final class DesktopPetHotKeyController {
    private static let signature: OSType = 0x41554248 // “AUBH”
    private static let showID: UInt32 = 1
    private static let hideID: UInt32 = 2

    private var eventHandler: EventHandlerRef?
    private var showHotKey: EventHotKeyRef?
    private var hideHotKey: EventHotKeyRef?
    private let actionHandler: (DesktopPetHotKeyAction) -> Void

    init(actionHandler: @escaping (DesktopPetHotKeyAction) -> Void) {
        self.actionHandler = actionHandler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return noErr }
                let controller = Unmanaged<DesktopPetHotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                return controller.handle(event)
            },
            1,
            &eventType,
            userData,
            &eventHandler
        )
    }

    deinit {
        unregister(&showHotKey)
        unregister(&hideHotKey)
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func update(show: PetShortcut, hide: PetShortcut) {
        unregister(&showHotKey)
        unregister(&hideHotKey)

        register(show, id: Self.showID, into: &showHotKey)
        // Equal shortcuts are rejected by DesktopPetStore, but keep this guard
        // here as a second line of defence if settings are edited externally.
        guard hide != show else { return }
        register(hide, id: Self.hideID, into: &hideHotKey)
    }

    private func register(
        _ shortcut: PetShortcut,
        id: UInt32,
        into destination: inout EventHotKeyRef?
    ) {
        guard shortcut.isValid else { return }
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &destination
        )
    }

    private func unregister(_ reference: inout EventHotKeyRef?) {
        if let registered = reference {
            UnregisterEventHotKey(registered)
            reference = nil
        }
    }

    private func handle(_ event: EventRef?) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == Self.signature else { return noErr }

        let action: DesktopPetHotKeyAction?
        switch hotKeyID.id {
        case Self.showID: action = .show
        case Self.hideID: action = .hide
        default: action = nil
        }
        guard let action else { return noErr }
        DispatchQueue.main.async { [weak self] in
            self?.actionHandler(action)
        }
        return noErr
    }
}

struct PetShortcutRecorder: NSViewRepresentable {
    let shortcut: PetShortcut
    let onRecord: (PetShortcut) -> Void

    func makeNSView(context: Context) -> PetShortcutRecorderView {
        let view = PetShortcutRecorderView()
        view.shortcut = shortcut
        view.onRecord = onRecord
        return view
    }

    func updateNSView(_ nsView: PetShortcutRecorderView, context: Context) {
        nsView.shortcut = shortcut
        nsView.onRecord = onRecord
    }
}

final class PetShortcutRecorderView: NSButton {
    var shortcut: PetShortcut? {
        didSet { updateTitle() }
    }
    var onRecord: ((PetShortcut) -> Void)?

    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.momentaryPushIn)
        bezelStyle = .rounded
        alignment = .center
        focusRingType = .default
        target = self
        action = #selector(beginRecording)
        updateTitle()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        target = self
        action = #selector(beginRecording)
        updateTitle()
    }

    @objc private func beginRecording() {
        isRecording = true
        updateTitle()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        // Escape cancels recording and leaves the previous shortcut intact.
        if event.keyCode == 53 {
            isRecording = false
            updateTitle()
            return
        }
        guard let shortcut = PetShortcut.from(event) else {
            NSSound.beep()
            return
        }
        isRecording = false
        updateTitle()
        onRecord?(shortcut)
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        updateTitle()
        return super.resignFirstResponder()
    }

    private func updateTitle() {
        title = isRecording
            ? PetUI.text("请按下快捷键…", "Press a shortcut…")
            : (shortcut?.displayName ?? "—")
    }
}

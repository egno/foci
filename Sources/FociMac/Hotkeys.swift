import Carbon.HIToolbox
import FociCore

/// Global hotkeys via Carbon `RegisterEventHotKey`: needs no Input Monitoring permission.
@MainActor
public final class Hotkeys {
    /// Receives the command script bound to the pressed key.
    public var onHotkey: ((String) -> Void)?

    private var refs: [EventHotKeyRef] = []
    private var scripts: [UInt32: String] = [:]
    private var handler: EventHandlerRef?

    public init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, refcon in
            guard let event, let refcon else { return OSStatus(eventNotHandledErr) }
            var hotkey = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &hotkey)
            guard status == noErr else { return status }
            let hotkeys = Unmanaged<Hotkeys>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { hotkeys.fire(hotkey.id) }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    /// Replaces all registered hotkeys. Returns problems (unknown keys, combos taken by another app).
    public func register(_ bindings: [KeyCombo: String]) -> [String] {
        for r in refs { UnregisterEventHotKey(r) }
        refs = []
        scripts = [:]
        var errors: [String] = []
        for (i, (combo, script)) in bindings.sorted(by: { $0.key.description < $1.key.description }).enumerated() {
            guard let code = Self.keyCodes[combo.key] else {
                errors.append("unknown key '\(combo.key)' in '\(combo)'")
                continue
            }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x464F_4349), id: UInt32(i))  // 'FOCI'
            let status = RegisterEventHotKey(
                UInt32(code), Self.carbonModifiers(combo.modifiers), id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                scripts[UInt32(i)] = script
            } else {
                errors.append("can't register '\(combo)' (taken by another app?)")
            }
        }
        return errors
    }

    private func fire(_ id: UInt32) {
        guard let script = scripts[id] else { return }
        // Not inside the Carbon handler: the command may re-register hotkeys (mode switch).
        DispatchQueue.main.async { [weak self] in self?.onHotkey?(script) }
    }

    private static func carbonModifiers(_ m: Set<Modifier>) -> UInt32 {
        var r = 0
        if m.contains(.cmd) { r |= cmdKey }
        if m.contains(.ctrl) { r |= controlKey }
        if m.contains(.alt) { r |= optionKey }
        if m.contains(.shift) { r |= shiftKey }
        return UInt32(r)
    }

    /// Physical keys of the ANSI (qwerty) layout.
    static let keyCodes: [String: Int] = {
        var k: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
            "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
            "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
            "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            "minus": kVK_ANSI_Minus, "equal": kVK_ANSI_Equal, "leftsquarebracket": kVK_ANSI_LeftBracket,
            "rightsquarebracket": kVK_ANSI_RightBracket, "backslash": kVK_ANSI_Backslash,
            "semicolon": kVK_ANSI_Semicolon, "quote": kVK_ANSI_Quote, "comma": kVK_ANSI_Comma,
            "period": kVK_ANSI_Period, "slash": kVK_ANSI_Slash, "backtick": kVK_ANSI_Grave,
            "space": kVK_Space, "enter": kVK_Return, "tab": kVK_Tab, "esc": kVK_Escape, "backspace": kVK_Delete,
            "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
            "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        ]
        let fKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ]
        for (i, code) in fKeys.enumerated() { k["f\(i + 1)"] = code }
        return k
    }()
}

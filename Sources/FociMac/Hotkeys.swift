import AppKit
import Carbon.HIToolbox
import FociCore

/// Global hotkeys via Carbon `RegisterEventHotKey`: needs no Input Monitoring permission.
/// Modifier keys tapped alone (`right-cmd`) can't be registered there: they are seen by an `NSEvent` monitor
/// of modifier changes, which needs the Accessibility permission Foci has anyway.
@MainActor
public final class Hotkeys {
    /// Receives the bound key that was pressed.
    public var onHotkey: ((KeyCombo) -> Void)?
    /// A key press that is no hotkey, or a mouse click, while `reportsOtherInput`. It still reaches the app:
    /// Foci only watches.
    public var onOtherInput: (() -> Void)?
    public var reportsOtherInput = false

    private var refs: [EventHotKeyRef] = []
    private var combos: [UInt32: KeyCombo] = [:]
    private var handler: EventHandlerRef?
    /// Tap key names of the current mode.
    private var tapKeys: Set<String> = []
    /// Registered (key code, modifiers), to tell other key presses from hotkeys.
    private var registered: Set<Chord> = []
    /// The set before the last `register`, and when it was replaced: the key that changed the mode may reach
    /// the monitor after the new set is registered.
    private var replaced: (chords: Set<Chord>, at: TimeInterval) = ([], 0)
    private var taps = TapDetector()
    private var monitors: [Any] = []

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

        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown]
        let handle: (NSEvent) -> Void = { [weak self] event in MainActor.assumeIsolated { self?.observe(event) } }
        // Global: events going to other apps. Local: to Foci itself (its menu, the key hints never take keys).
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handle) as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: mask) { handle($0); return $0 } as Any)
    }

    /// Replaces all registered hotkeys. Returns problems (unknown keys, combos taken by another app).
    public func register(_ bindings: [KeyCombo: String]) -> [String] {
        for r in refs { UnregisterEventHotKey(r) }
        refs = []
        combos = [:]
        tapKeys = []
        replaced = (registered, GetCurrentEventTime())
        registered = []
        var errors: [String] = []
        for (i, combo) in bindings.keys.sorted(by: { $0.description < $1.description }).enumerated() {
            if KeyCombo.tapKeys.contains(combo.key) {
                tapKeys.insert(combo.key)
                continue
            }
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
                combos[UInt32(i)] = combo
                registered.insert(Chord(code: code, modifiers: combo.modifiers))
            } else {
                errors.append("can't register '\(combo)' (taken by another app?)")
            }
        }
        return errors
    }

    private func fire(_ id: UInt32) {
        guard let combo = combos[id] else { return }
        // Not inside the Carbon handler: the command may re-register hotkeys (mode switch).
        DispatchQueue.main.async { [weak self] in self?.onHotkey?(combo) }
    }

    private func observe(_ event: NSEvent) {
        if event.type == .flagsChanged, let key = TapDetector.keys[Int(event.keyCode)] {
            let down = event.modifierFlags.rawValue & key.deviceMask != 0
            if let tapped = taps.modifier(key.name, down: down, at: event.timestamp), tapKeys.contains(tapped) {
                let combo = KeyCombo(modifiers: [], key: tapped)
                DispatchQueue.main.async { [weak self] in self?.onHotkey?(combo) }
            }
            return
        }
        taps.interrupt()  // a key or click while the modifier is held: a shortcut, not a tap
        guard reportsOtherInput, event.type != .flagsChanged, event.type != .keyDown || !isHotkey(event) else { return }
        DispatchQueue.main.async { [weak self] in self?.onOtherInput?() }
    }

    private func isHotkey(_ event: NSEvent) -> Bool {
        let chord = Chord(event)
        return registered.contains(chord) || (event.timestamp <= replaced.at && replaced.chords.contains(chord))
    }

    private static func carbonModifiers(_ m: Set<Modifier>) -> UInt32 {
        var r = 0
        if m.contains(.cmd) { r |= cmdKey }
        if m.contains(.ctrl) { r |= controlKey }
        if m.contains(.alt) { r |= optionKey }
        if m.contains(.shift) { r |= shiftKey }
        return UInt32(r)
    }

    struct Chord: Hashable {
        let code: Int
        let modifiers: Set<Modifier>

        init(code: Int, modifiers: Set<Modifier>) {
            self.code = code; self.modifiers = modifiers
        }

        init(_ event: NSEvent) {
            let flags = event.modifierFlags
            var m = Set<Modifier>()
            if flags.contains(.command) { m.insert(.cmd) }
            if flags.contains(.control) { m.insert(.ctrl) }
            if flags.contains(.option) { m.insert(.alt) }
            if flags.contains(.shift) { m.insert(.shift) }
            self.init(code: Int(event.keyCode), modifiers: m)
        }
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

/// A modifier key pressed and released alone, quickly, with nothing else pressed in between.
struct TapDetector {
    struct Key {
        let name: String
        /// Device-dependent bit of `NSEvent.modifierFlags` (NX_DEVICE*KEYMASK): tells left from right.
        let deviceMask: UInt
    }

    static let keys: [Int: Key] = [
        kVK_Command: Key(name: "left-cmd", deviceMask: 0x08), kVK_RightCommand: Key(name: "right-cmd", deviceMask: 0x10),
        kVK_Option: Key(name: "left-alt", deviceMask: 0x20), kVK_RightOption: Key(name: "right-alt", deviceMask: 0x40),
        kVK_Control: Key(name: "left-ctrl", deviceMask: 0x01), kVK_RightControl: Key(name: "right-ctrl", deviceMask: 0x2000),
        kVK_Shift: Key(name: "left-shift", deviceMask: 0x02), kVK_RightShift: Key(name: "right-shift", deviceMask: 0x04),
    ]

    /// Longer holds are not taps (holding ⌘ while deciding on a shortcut).
    static let maxDuration: TimeInterval = 0.5

    private var pressed: (key: String, at: TimeInterval)?

    /// Returns the key if this release completes a tap.
    mutating func modifier(_ key: String, down: Bool, at time: TimeInterval) -> String? {
        if down {
            // A second modifier while one is held (⌘⇧): a chord, not a tap.
            pressed = pressed == nil ? (key, time) : nil
            return nil
        }
        defer { pressed = nil }
        guard let p = pressed, p.key == key, time - p.at <= Self.maxDuration else { return nil }
        return key
    }

    mutating func interrupt() { pressed = nil }
}

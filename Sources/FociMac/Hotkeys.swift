import AppKit
import Carbon.HIToolbox
import FociCore

/// Global hotkeys via Carbon `RegisterEventHotKey`: needs no Input Monitoring permission.
/// Modifier keys tapped alone (`right-cmd`) can't be registered there: they are seen by an `NSEvent` monitor
/// of modifier changes, which needs the Accessibility permission Foci has anyway. Plain keys held down
/// (`hold-space`) go through a keyboard event tap, see `HoldDetector`.
@MainActor
public final class Hotkeys {
    /// Receives the bound key that was pressed.
    public var onHotkey: ((KeyCombo) -> Void)?
    /// A key press that is no hotkey, or a mouse click, while `reportsOtherInput`. It still reaches the app:
    /// Foci only watches.
    public var onOtherInput: (() -> Void)?
    public var reportsOtherInput = false
    /// Seconds a `hold-` key must be held down to act.
    public var holdDelay: TimeInterval = 0.25

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
    private var holds = HoldDetector()
    private var holdTap: CFMachPort?

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
        holds.keys = [:]
        for combo in bindings.keys {
            guard let held = combo.heldKey else { continue }
            guard let code = Self.keyCodes[held] else {
                errors.append("unknown key '\(held)' in '\(combo)'")
                continue
            }
            // Tapped, the key itself: bound in this mode, or typed.
            let plain = KeyCombo(modifiers: [], key: held)
            holds.keys[code] = (combo, bindings[plain] == nil ? nil : plain)
        }
        if !holds.keys.isEmpty, let error = installHoldTap() { errors.append(error) }
        let heldCodes = Set(holds.keys.keys)
        for (i, combo) in bindings.keys.sorted(by: { $0.description < $1.description }).enumerated() {
            if KeyCombo.tapKeys.contains(combo.key) {
                tapKeys.insert(combo.key)
                continue
            }
            if combo.heldKey != nil { continue }
            // The event tap sees the key first and runs it when tapped.
            if combo.modifiers.isEmpty, let code = Self.keyCodes[combo.key], heldCodes.contains(code) { continue }
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

    /// Keyboard event tap for `hold-` keys: kept once installed, it passes everything through while no `hold-`
    /// key is bound.
    private func installHoldTap() -> String? {
        if holdTap != nil { return nil }
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let hotkeys = Unmanaged<Hotkeys>.fromOpaque(refcon).takeUnretainedValue()
            // Runs on the main run loop.
            nonisolated(unsafe) let (proxy, event) = (proxy, event)
            nonisolated(unsafe) var result: Unmanaged<CGEvent>?
            MainActor.assumeIsolated { result = hotkeys.handleHoldTap(proxy, type, event) }
            return result
        }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: CGEventMask(mask), callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return "can't watch held keys: no Accessibility permission?" }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        holdTap = tap
        return nil
    }

    private func handleHoldTap(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let holdTap { CGEvent.tapEnable(tap: holdTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let plain = event.flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate, .maskShift])
        let repeating = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let action = holds.key(code, down: type == .keyDown, plain: plain, repeating: repeating)
        switch action {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .swallow:
            return nil
        case .wait(let combo):
            let id = holds.pressID
            DispatchQueue.main.asyncAfter(deadline: .now() + holdDelay) { [weak self] in
                guard let self, self.holds.held(id) else { return }
                self.onHotkey?(combo)
            }
            return nil
        case .tapped(let combo):
            if let combo {
                DispatchQueue.main.async { [weak self] in self?.onHotkey?(combo) }
            } else {
                Self.post(code, down: true, like: event, proxy)
                Self.post(code, down: false, like: event, proxy)
            }
            return nil
        case .typing(let held):
            // Another key while held briefly: typing fast, the held key first. Copies keep the order.
            Self.post(held, down: true, like: event, proxy)
            event.copy().map { $0.tapPostEvent(proxy) }
            return nil
        }
    }

    private static func post(_ code: Int, down: Bool, like event: CGEvent, _ proxy: CGEventTapProxy) {
        guard let e = CGEvent(keyboardEventSource: CGEventSource(event: event), virtualKey: CGKeyCode(code), keyDown: down)
        else { return }
        e.flags = event.flags
        e.tapPostEvent(proxy)
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

/// A plain key that acts when held down (`hold-space`): its press is held back until it is released (the key
/// is typed, or runs its own binding), another key comes (typing fast: typed), or it is held `holdDelay`.
struct HoldDetector {
    enum Action: Equatable {
        case pass, swallow
        /// Held back: acts as the combo if still held after the delay.
        case wait(KeyCombo)
        /// Released before the delay: run the combo, or type the key if nil.
        case tapped(KeyCombo?)
        /// Another key during the wait: type the held key (code) first, then that key.
        case typing(Int)
    }

    /// Key code → the `hold-` combo, and the plain key's own binding in this mode.
    var keys: [Int: (hold: KeyCombo, plain: KeyCombo?)] = [:]
    /// Counts presses, so a delay that ends after the key was released does nothing.
    private(set) var pressID = 0

    private enum State {
        case waiting(code: Int, plain: KeyCombo?, id: Int)
        /// Acted after the delay: the rest of this press is Foci's.
        case acted(code: Int)
        /// Typed: the rest of this press goes to the app.
        case typed(code: Int)
    }
    private var state: State?

    mutating func key(_ code: Int, down: Bool, plain: Bool, repeating: Bool) -> Action {
        switch state {
        case .waiting(let held, let binding, _) where held == code:
            if down { return .swallow }
            state = nil
            return .tapped(binding)
        case .waiting(let held, _, _):
            guard down else { return .pass }
            state = .typed(code: held)
            return .typing(held)
        case .acted(let held) where held == code:
            if !down { state = nil }
            return .swallow
        case .typed(let held) where held == code:
            if !down { state = nil }
            return .pass
        case .acted, .typed:
            return .pass
        case nil:
            guard down, !repeating, plain, let hold = keys[code] else { return .pass }
            pressID += 1
            state = .waiting(code: code, plain: hold.plain, id: pressID)
            return .wait(hold.hold)
        }
    }

    /// The delay of press `id` ended: true if it should act now.
    mutating func held(_ id: Int) -> Bool {
        guard case .waiting(let code, _, let current) = state, current == id else { return false }
        state = .acted(code: code)
        return true
    }
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

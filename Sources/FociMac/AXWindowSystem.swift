import AppKit
import ApplicationServices
import FociCore
import os

/// `WindowSystem` over the Accessibility API. Also observes AX notifications and reports them via `onEvent`.
@MainActor
public final class AXWindowSystem: WindowSystem {
    /// Something changed (window created/destroyed/focused, title changed, ...): the engine should refresh.
    public var onEvent: (() -> Void)?

    private struct Entry {
        let element: AXUIElement
        let pid: pid_t
        var frame: Rect
    }
    private var windowsByID: [WindowID: Entry] = [:]
    private var apps: [pid_t: AXUIElement] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var observedWindows: Set<WindowID> = []
    private var args: [pid_t: String] = [:]
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let log = Logger(subsystem: "dev.foci", category: "ax")
    /// Last logged enumeration summary, to log only changes.
    private var lastSummary = ""
    /// Windows per app from the last successful enumeration.
    private var lastSeen: [pid_t: [WindowID: (entry: Entry, facts: WindowFacts)]] = [:]

    public init() {}

    public static func isTrusted(prompt: Bool) -> Bool {
        let key = "AXTrustedCheckOptionPrompt"  // kAXTrustedCheckOptionPrompt is not concurrency-safe in Swift 6
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    // MARK: - WindowSystem

    public func displays() -> [Display] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return [] }
        // NSScreen: origin bottom-left of the primary display, y up. AX: origin top-left, y down.
        func ax(_ r: NSRect) -> Rect { Rect(x: r.minX, y: primary.frame.height - r.maxY, width: r.width, height: r.height) }
        return screens.map { s in
            let number = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return Display(
                id: DisplayID(number?.uint32Value ?? 0), name: s.localizedName, frame: ax(s.frame),
                visibleFrame: ax(s.visibleFrame), isMain: s == primary)
        }
    }

    public func windows() -> [WindowFacts] {
        var result: [WindowFacts] = []
        var seen: [WindowID: Entry] = [:]
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ownPID && !$0.isTerminated
        }
        let pids = Set(running.map(\.processIdentifier))
        for pid in apps.keys where !pids.contains(pid) { forget(pid) }

        var summary: [String] = []
        for app in running {
            let pid = app.processIdentifier
            let axApp = appElement(pid)
            observe(pid, axApp)
            let name = app.localizedName ?? "?"
            var value: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)
            guard err == .success, let elements = value as? [AXUIElement] else {
                // A busy app (AXError -25204) must not look like it closed its windows: that would drop
                // their project links. Report what we saw last time.
                let cached = lastSeen[pid] ?? [:]
                summary.append("\(name)[\(pid)]: AXError \(err.rawValue), reusing \(cached.count) window(s)")
                for (id, e) in cached {
                    seen[id] = e.entry
                    result.append(e.facts)
                }
                continue
            }
            let commandLine = args[pid] ?? ProcessArgs.commandLine(pid: pid) ?? ""
            args[pid] = commandLine
            var appSeen: [WindowID: (entry: Entry, facts: WindowFacts)] = [:]
            for w in elements {
                let subrole: String? = w.attribute(kAXSubroleAttribute)
                guard Self.isManageable(w, subrole: subrole),
                    let raw = w.windowID, let pos = w.point(kAXPositionAttribute), let size = w.size(kAXSizeAttribute)
                else {
                    summary.append(
                        "\(name)[\(pid)]: skipped \(w.windowID.map(String.init) ?? "nil"), subrole \(subrole ?? "nil"), "
                            + "buttons \(Self.buttons(w))")
                    continue
                }
                let id = WindowID(raw)
                let frame = Rect(x: pos.x, y: pos.y, width: size.width, height: size.height)
                let frozen = app.isHidden || (w.attribute(kAXMinimizedAttribute) as Bool?) == true
                    || (w.attribute("AXFullScreen") as Bool?) == true
                let facts = WindowFacts(
                    id: id, pid: pid, bundleID: app.bundleIdentifier, appName: name, appArgs: commandLine,
                    title: (w.attribute(kAXTitleAttribute) as String?) ?? "", frame: frame, isFrozen: frozen)
                result.append(facts)
                summary.append("\(name)[\(pid)]: \(id) \(subrole ?? "") \(frame)\(frozen ? " frozen" : "")")
                let entry = Entry(element: w, pid: pid, frame: frame)
                seen[id] = entry
                appSeen[id] = (entry, facts)
                observeWindow(id, w, pid)
            }
            lastSeen[pid] = appSeen
        }
        let joined = summary.sorted().joined(separator: "\n")
        if joined != lastSummary {
            lastSummary = joined
            log.info("windows:\n\(joined, privacy: .public)")
        }
        windowsByID = seen
        observedWindows.formIntersection(seen.keys)
        return result
    }

    public func focusedWindow() -> WindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ownPID,
            let w: AXUIElement = appElement(app.processIdentifier).attribute(kAXFocusedWindowAttribute),
            let raw = w.windowID
        else { return nil }
        return WindowID(raw)
    }

    public func setFrame(_ id: WindowID, _ frame: Rect) {
        guard var e = windowsByID[id] else { return }
        let app = appElement(e.pid)
        // Apps with "enhanced user interface" (set by VoiceOver-aware tools) animate every AX resize.
        let enhanced = (app.attribute("AXEnhancedUserInterface") as Bool?) == true
        if enhanced { app.set("AXEnhancedUserInterface", kCFBooleanFalse) }
        let pos = CGPoint(x: frame.x, y: frame.y)
        if abs(e.frame.width - frame.width) > 0.5 || abs(e.frame.height - frame.height) > 0.5 {
            // Position, size, position: a resize may be clamped by the old position on the display edge.
            e.element.set(kAXPositionAttribute, point: pos)
            e.element.set(kAXSizeAttribute, size: CGSize(width: frame.width, height: frame.height))
        }
        e.element.set(kAXPositionAttribute, point: pos)
        if enhanced { app.set("AXEnhancedUserInterface", kCFBooleanTrue) }
        e.frame = frame
        windowsByID[id] = e
    }

    public func focus(_ id: WindowID) {
        guard let e = windowsByID[id] else { return }
        WindowFocus.focus(window: e.element, id: id.raw, pid: e.pid)
    }

    /// Standard windows, plus "dialogs" that behave like main windows: Outlook's main window is an AXDialog.
    /// Real dialogs have no minimize or zoom button.
    static func isManageable(_ w: AXUIElement, subrole: String?) -> Bool {
        if subrole == kAXStandardWindowSubrole { return true }
        guard subrole == kAXDialogSubrole else { return false }
        let minimize: AXUIElement? = w.attribute(kAXMinimizeButtonAttribute)
        let zoom: AXUIElement? = w.attribute(kAXZoomButtonAttribute)
        return minimize != nil || zoom != nil
    }

    private static func buttons(_ w: AXUIElement) -> String {
        [(kAXCloseButtonAttribute, "close"), (kAXMinimizeButtonAttribute, "min"), (kAXZoomButtonAttribute, "zoom"),
         (kAXFullScreenButtonAttribute, "full")]
            .filter { (w.attribute($0.0) as AXUIElement?) != nil }.map(\.1).joined(separator: ",")
    }

    // MARK: - Observation

    private func appElement(_ pid: pid_t) -> AXUIElement {
        if let e = apps[pid] { return e }
        let e = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(e, 0.5)  // a hung app must not freeze Foci
        apps[pid] = e
        return e
    }

    private func forget(_ pid: pid_t) {
        if let o = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode)
        }
        apps[pid] = nil
        args[pid] = nil
        lastSeen[pid] = nil
    }

    private static let appNotifications = [
        kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
        kAXApplicationHiddenNotification, kAXApplicationShownNotification,
    ]
    private static let windowNotifications = [
        kAXUIElementDestroyedNotification, kAXTitleChangedNotification, kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
    ]

    private func observe(_ pid: pid_t, _ axApp: AXUIElement) {
        guard observers[pid] == nil else { return }
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let system = Unmanaged<AXWindowSystem>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { system.onEvent?() }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in Self.appNotifications { AXObserverAddNotification(observer, axApp, n as CFString, refcon) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func observeWindow(_ id: WindowID, _ w: AXUIElement, _ pid: pid_t) {
        guard !observedWindows.contains(id), let observer = observers[pid] else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in Self.windowNotifications { AXObserverAddNotification(observer, w, n as CFString, refcon) }
        observedWindows.insert(id)
    }
}

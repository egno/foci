import AppKit
import Darwin

// Probe: the fixture app of Tests/E2E. Standard titled windows, controlled over a Unix socket.
//
//   open -gna "$E2E_DIR/apps/Probe B.app" --args --group alpha --title 'alpha term' --ctl at
//
//   --group <g>    only stays in the process arguments: Foci matches `args` rules on the command line
//   --title <t>    title of the first window (none without it)
//   --ctl <name>   control socket $E2E_DIR/ctl/<name>.sock, line commands with one reply line (`ok ...`/`err ...`)
//   --size WxH     size of new windows (default 800x600)
//
// $E2E_DIR is the directory above `apps/` that holds this bundle (or the environment variable).

// MARK: - Options and log

struct Options {
    var title: String?
    var ctl: String?
    var size = CGSize(width: 800, height: 600)

    init(_ args: [String]) {
        var i = 1
        while i < args.count {
            let next = i + 1 < args.count ? args[i + 1] : nil
            switch args[i] {
            case "--title": title = next; i += 1
            case "--ctl": ctl = next; i += 1
            case "--group": i += 1
            case "--size":
                let p = (next ?? "").split(separator: "x").compactMap { Double($0) }
                if p.count == 2 { size = CGSize(width: p[0], height: p[1]) }
                i += 1
            default: break
            }
            i += 1
        }
    }
}

let options = Options(CommandLine.arguments)

/// /private/tmp is /tmp: the short spelling keeps socket paths below the 104 byte limit.
func short(_ path: String) -> String { path.hasPrefix("/private/tmp/") ? String(path.dropFirst(8)) : path }

let e2eDir: String = {
    if let d = ProcessInfo.processInfo.environment["E2E_DIR"] { return short(d) }
    let bundle = URL(fileURLWithPath: Bundle.main.bundlePath)
    return short(bundle.deletingLastPathComponent().deletingLastPathComponent().path)
}()
let logPath = ProcessInfo.processInfo.environment["E2E_LOG"] ?? e2eDir + "/e2e.log"

func log(_ line: String) {
    let fd = open(logPath, O_WRONLY | O_APPEND | O_CREAT, 0o644)
    guard fd >= 0 else { return }
    let data = Array((line + "\n").utf8)
    _ = data.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
    close(fd)
}

// MARK: - Windows

struct CtlError: Error { let message: String }

/// Global Accessibility coordinates: origin top-left of the primary display, y down.
func primaryHeight() -> CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

final class Probe: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var registry: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let item = NSMenuItem()
        menu.addItem(item)
        let sub = NSMenu()
        sub.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = sub
        NSApp.mainMenu = menu
        if let t = options.title { _ = newWindow(t) }
        log("probe-start \(options.ctl ?? "-") " + CommandLine.arguments.dropFirst().joined(separator: " "))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func windowWillClose(_ notification: Notification) {
        registry.removeAll { $0 === notification.object as? NSWindow }
    }

    func newWindow(_ title: String) -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: options.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        w.isRestorable = false
        w.tabbingMode = .disallowed
        w.collectionBehavior.insert(.fullScreenPrimary)
        w.delegate = self
        let label = NSTextField(labelWithString: "\(title)\n\(options.ctl ?? "")")
        label.alignment = .center
        w.contentView = label
        w.center()
        // Cascade a little so windows can be told apart, without activating the app (a background launch).
        w.setFrameOrigin(NSPoint(x: w.frame.origin.x + CGFloat(registry.count) * 30, y: w.frame.origin.y - CGFloat(registry.count) * 30))
        registry.append(w)
        w.orderFrontRegardless()
        return w
    }

    func window(_ title: String) throws -> NSWindow {
        guard let w = registry.first(where: { $0.title == title }) else { throw CtlError(message: "no window '\(title)'") }
        return w
    }

    /// Frame as the window server has it (also while parked off-screen), in Accessibility coordinates.
    func axFrame(_ w: NSWindow) -> CGRect {
        let number = w.windowNumber
        if let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]],
            let info = list.first(where: { ($0[kCGWindowNumber as String] as? Int) == number }),
            let b = info[kCGWindowBounds as String] as? [String: Any],
            let x = (b["X"] as? NSNumber)?.doubleValue, let y = (b["Y"] as? NSNumber)?.doubleValue,
            let width = (b["Width"] as? NSNumber)?.doubleValue, let height = (b["Height"] as? NSNumber)?.doubleValue
        {
            return CGRect(x: x, y: y, width: width, height: height)
        }
        let f = w.frame
        return CGRect(x: f.minX, y: primaryHeight() - f.maxY, width: f.width, height: f.height)
    }

    func isFullScreen(_ w: NSWindow) -> Bool { w.styleMask.contains(.fullScreen) }

    // MARK: Focus

    private typealias SetFrontProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32) -> CGError
    private typealias ProcessForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias PostEventRecord = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError

    /// Activates the app and makes the window key. `activate` works from the background here; if the window is not
    /// key a moment later, the private SkyLight calls Foci's `WindowFocus` uses force it.
    func focus(_ w: NSWindow) {
        if w.isMiniaturized { w.deminiaturize(nil) }
        if NSRunningApplication.current.isHidden { NSRunningApplication.current.unhide() }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if !w.isKeyWindow || !NSApp.isActive { self.forceFocus(w) }
        }
    }

    func forceFocus(_ w: NSWindow) {
        let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        func sym<T>(_ name: String, _ handle: UnsafeMutableRawPointer?) -> T? {
            guard let handle, let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        let setFront: SetFrontProcess? = sym("_SLPSSetFrontProcessWithOptions", skyLight)
        let post: PostEventRecord? = sym("SLPSPostEventRecordTo", skyLight)
        let processForPID: ProcessForPID? = sym("GetProcessForPID", UnsafeMutableRawPointer(bitPattern: -2))
        var psn = ProcessSerialNumber()
        guard let setFront, let post, let processForPID, processForPID(getpid(), &psn) == noErr else { return }
        let id = CGWindowID(w.windowNumber)
        _ = setFront(&psn, id, 0x200)
        for kind: UInt8 in [1, 2] {
            var bytes = [UInt8](repeating: 0, count: 0xf8)
            bytes[0x04] = 0xf8
            bytes[0x08] = kind
            bytes[0x3a] = 0x10
            withUnsafeBytes(of: id) { for (i, b) in $0.enumerated() { bytes[0x3c + i] = b } }
            for i in 0x20..<0x30 { bytes[i] = 0xff }
            _ = bytes.withUnsafeMutableBufferPointer { post(&psn, $0.baseAddress!) }
        }
        w.makeKeyAndOrderFront(nil)
    }

    // MARK: Commands

    func number(_ s: String?) throws -> Double {
        guard let s, let d = Double(s) else { throw CtlError(message: "expected a number, got '\(s ?? "")'") }
        return d
    }

    func fmt(_ r: CGRect) -> String {
        [r.minX, r.minY, r.width, r.height].map { (c: CGFloat) -> String in
            let rounded = (Double(c) * 100).rounded() / 100
            return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        }.joined(separator: " ")
    }

    func json(_ object: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Runs on the main thread. `spawn` is handled by the connection thread.
    func run(_ words: [String]) throws -> String {
        guard let cmd = words.first else { throw CtlError(message: "empty command") }
        let a = Array(words.dropFirst())
        func arg(_ i: Int) throws -> String {
            guard i < a.count else { throw CtlError(message: "\(cmd): missing argument") }
            return a[i]
        }
        switch cmd {
        case "ping": return "ok"
        case "pid": return "ok \(getpid())"
        case "new-window":
            return "ok \(newWindow(a.first ?? "Probe").windowNumber)"
        case "close":
            try window(try arg(0)).close()
            return "ok"
        case "rename":
            try window(try arg(0)).title = try arg(1)
            return "ok"
        case "focus":
            focus(try window(try arg(0)))
            return "ok"
        case "frame":
            return "ok " + fmt(axFrame(try window(try arg(0))))
        case "id":
            return "ok \(try window(try arg(0)).windowNumber)"
        case "move":
            let w = try window(try arg(0))
            let x = try number(a.count > 1 ? a[1] : nil), y = try number(a.count > 2 ? a[2] : nil)
            let width = try number(a.count > 3 ? a[3] : nil), height = try number(a.count > 4 ? a[4] : nil)
            w.setFrame(NSRect(x: x, y: primaryHeight() - y - height, width: width, height: height), display: true)
            return "ok"
        case "minimize":
            try window(try arg(0)).miniaturize(nil)
            return "ok"
        case "unminimize":
            try window(try arg(0)).deminiaturize(nil)
            return "ok"
        case "fullscreen":
            try window(try arg(0)).toggleFullScreen(nil)
            return "ok"
        case "hide":
            NSRunningApplication.current.hide()
            return "ok"
        case "unhide":
            NSRunningApplication.current.unhide()
            return "ok"
        case "list":
            return "ok " + json(registry.map { w -> [String: Any] in
                ["id": w.windowNumber, "title": w.title, "minimized": w.isMiniaturized,
                 "fullscreen": isFullScreen(w), "frame": fmt(axFrame(w))]
            })
        case "state":
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid()
            return "ok " + json([
                "pid": Int(getpid()), "frontmost": front, "hidden": NSRunningApplication.current.isHidden,
                "key": NSApp.keyWindow.map { $0.title as Any } ?? NSNull(), "active": NSApp.isActive,
                "main": NSApp.mainWindow.map { $0.title as Any } ?? NSNull(),
            ])
        case "quit":
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exit(0) }
            return "ok"
        default:
            throw CtlError(message: "unknown command '\(cmd)'")
        }
    }
}

// MARK: - Control socket

/// Words separated by blanks; '...' and "..." group, backslash escapes.
func tokenize(_ line: String) -> [String] {
    var words: [String] = []
    var cur = ""
    var inWord = false
    var quote: Character?
    var escaped = false
    for ch in line {
        if escaped { cur.append(ch); escaped = false; continue }
        if ch == "\\" && quote != "'" { escaped = true; inWord = true; continue }
        if let q = quote {
            if ch == q { quote = nil } else { cur.append(ch) }
        } else if ch == "'" || ch == "\"" {
            quote = ch; inWord = true
        } else if ch == " " || ch == "\t" {
            if inWord { words.append(cur); cur = ""; inWord = false }
        } else {
            cur.append(ch); inWord = true
        }
    }
    if inWord { words.append(cur) }
    return words
}

func spawn(_ command: String) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", command]
    var env = ProcessInfo.processInfo.environment
    env["E2E_DIR"] = env["E2E_DIR"] ?? e2eDir
    env["E2E_LOG"] = env["E2E_LOG"] ?? logPath
    env["FOCI_HOME"] = env["FOCI_HOME"] ?? e2eDir + "/home"
    p.environment = env
    p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
    p.standardInput = FileHandle.nullDevice
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do {
        try p.run()
        p.waitUntilExit()
        return "ok \(p.terminationStatus)"
    } catch {
        return "err \(error)"
    }
}

func handle(_ line: String, probe: Probe) -> String {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("spawn ") || trimmed == "spawn" {
        return spawn(String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces))
    }
    var reply = "err internal"
    defer { if trimmed.hasPrefix("focus ") { Thread.sleep(forTimeInterval: 0.25) } }
    DispatchQueue.main.sync {
        do { reply = try probe.run(tokenize(trimmed)) } catch let e as CtlError { reply = "err \(e.message)" } catch { reply = "err \(error)" }
    }
    return reply.replacingOccurrences(of: "\n", with: " ")
}

func serve(name: String, probe: Probe) {
    let dir = e2eDir + "/ctl"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    // Relative bind: the socket path limit applies to the name only.
    chdir(dir)
    let file = name + ".sock"
    unlink(file)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(file.utf8)
    guard fd >= 0, bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
        log("probe-error \(name) bad socket name")
        return
    }
    withUnsafeMutableBytes(of: &addr.sun_path) { buf in
        for (i, b) in bytes.enumerated() { buf[i] = b }
    }
    let size = socklen_t(MemoryLayout<sockaddr_un>.size)
    let ok = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) } == 0
    }
    guard ok, listen(fd, 16) == 0 else {
        log("probe-error \(name) can't listen: \(String(cString: strerror(errno)))")
        return
    }
    chdir(NSHomeDirectory())
    signal(SIGPIPE, SIG_IGN)
    Thread.detachNewThread {
        while true {
            let c = accept(fd, nil, nil)
            if c < 0 { continue }
            Thread.detachNewThread {
                var buffer = Data()
                var chunk = [UInt8](repeating: 0, count: 4096)
                while true {
                    let n = read(c, &chunk, chunk.count)
                    if n <= 0 { break }
                    buffer.append(contentsOf: chunk[0..<n])
                    while let nl = buffer.firstIndex(of: 0x0A) {
                        let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
                        buffer.removeSubrange(buffer.startIndex...nl)
                        let out = Array((handle(line, probe: probe) + "\n").utf8)
                        _ = out.withUnsafeBufferPointer { write(c, $0.baseAddress, $0.count) }
                    }
                }
                close(c)
            }
        }
    }
}

// MARK: - Main

let app = NSApplication.shared
let probe = Probe()
app.delegate = probe
app.setActivationPolicy(.regular)
if let ctl = options.ctl { serve(name: ctl, probe: probe) }
app.run()

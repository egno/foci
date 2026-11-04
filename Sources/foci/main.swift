import AppKit
import FociMac

// `foci <args>`: CLI client talking to the running app. Finder/`open` pass no arguments.
let cliArgs = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }
if !cliArgs.isEmpty {
    exit(MainActor.assumeIsolated { CLIClient.run(Array(cliArgs)) })
}

// Started from a terminal (`foci` with no arguments): macOS would check the terminal's Accessibility permission,
// not Foci's. Start the app through Launch Services instead, as Finder does. Not for test instances (FOCI_HOME).
if getppid() != 1, !FociPaths.isOverridden, let app = appBundle() {
    FileHandle.standardError.write("starting \(app.path)\n".data(using: .utf8)!)
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = [app.path]
    try? open.run()
    open.waitUntilExit()
    exit(open.terminationStatus)
}

/// The Foci.app this binary is in, also when it runs through a symlink (Homebrew's `foci`).
func appBundle() -> URL? {
    guard let path = Bundle.main.executablePath else { return nil }
    let app = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return app.pathExtension == "app" ? app : nil
}

// One instance only: two would fight over the same windows.
let lockPath = FociPaths.support().appending(path: "foci.lock").path
try? FileManager.default.createDirectory(
    atPath: (lockPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
let lockFD = open(lockPath, O_CREAT | O_RDWR, 0o600)
if lockFD < 0 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    FileHandle.standardError.write("foci is already running\n".data(using: .utf8)!)
    exit(1)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = FociApp()
    app.delegate = delegate
    app.run()
}

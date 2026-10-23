import AppKit
import FociMac

// One instance only: two would fight over the same windows.
let lockPath = URL.applicationSupportDirectory.appending(path: "Foci/foci.lock").path
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

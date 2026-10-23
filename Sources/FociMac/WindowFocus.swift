import AppKit

/// Focuses one specific window, also when Foci (a background agent) is not the active app.
/// Uses the private SkyLight calls yabai and AeroSpace rely on; falls back to public API.
@MainActor
enum WindowFocus {
    private typealias SetFrontProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32) -> CGError
    private typealias ProcessForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias PostEventRecord = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let setFrontProcess: SetFrontProcess? = symbol("_SLPSSetFrontProcessWithOptions")
    private static let postEventRecord: PostEventRecord? = symbol("SLPSPostEventRecordTo")
    // Deprecated, hence unavailable in Swift, but still the only way to get a PSN for these calls.
    private static let processForPID: ProcessForPID? = symbol("GetProcessForPID", in: UnsafeMutableRawPointer(bitPattern: -2))

    private static func symbol<T>(_ name: String, in handle: UnsafeMutableRawPointer? = skyLight) -> T? {
        guard let handle, let p = dlsym(handle, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    static func focus(window: AXUIElement, id: CGWindowID, pid: pid_t) {
        var psn = ProcessSerialNumber()
        if let setFrontProcess, let postEventRecord, let processForPID, processForPID(pid, &psn) == noErr {
            _ = setFrontProcess(&psn, id, 0x200)  // kCPSUserGenerated
            // Make it the key window: two synthetic event records, as in yabai's window_manager_make_key_window.
            for kind: UInt8 in [1, 2] {
                var bytes = [UInt8](repeating: 0, count: 0xf8)
                bytes[0x04] = 0xf8
                bytes[0x08] = kind
                bytes[0x3a] = 0x10
                withUnsafeBytes(of: id) { idBytes in
                    for (i, b) in idBytes.enumerated() { bytes[0x3c + i] = b }
                }
                for i in 0x20..<0x30 { bytes[i] = 0xff }
                _ = bytes.withUnsafeMutableBufferPointer { postEventRecord(&psn, $0.baseAddress!) }
            }
        } else {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
        window.set(kAXMainAttribute, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
}

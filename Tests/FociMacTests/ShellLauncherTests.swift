import Foundation
import Testing

@testable import FociMac

@MainActor
struct ShellLauncherTests {
    @Test func dropsTheTerminalSessionFociWasStartedFrom() {
        let env = ShellLauncher.inheritable([
            "HOME": "/Users/av", "PATH": "/usr/bin", "HERDR_ENV": "1", "HERDR_PANE_ID": "w1:p1",
            "KITTY_PID": "2724", "TERM_PROGRAM": "herdr", "TERM_PROGRAM_VERSION": "0.9.5", "TMUX": "/tmp/t",
        ])
        #expect(env == ["HOME": "/Users/av", "PATH": "/usr/bin"])
    }

    @Test func spawnsWithTheGivenEnvironmentAndDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pid = try ShellLauncher.spawnDisclaimed(
            "/bin/sh", ["-c", "echo \"$FOO $(pwd)\" > out"], environment: ["FOO": "bar"],
            directory: dir.path)
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        let out = try String(contentsOf: dir.appending(path: "out"), encoding: .utf8)
        let real = String(cString: realpath(dir.path, nil))
        #expect(out == "bar \(real)\n")
    }
}

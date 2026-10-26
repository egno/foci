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
}

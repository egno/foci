import FociCore
import Foundation
import os

/// Runs commands in a login shell so PATH matches the terminal (Homebrew, ~/.local/bin, ...).
@MainActor
public final class ShellLauncher: Launcher {
    private let log = Logger(subsystem: "dev.foci", category: "launch")

    public init() {}

    public func run(_ shellCommand: String, environment: [String: String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", shellCommand]
        p.environment = Self.inheritable(ProcessInfo.processInfo.environment).merging(environment) { _, new in new }
        p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            log.info("launched: \(shellCommand, privacy: .public)")
        } catch {
            log.error("can't run '\(shellCommand, privacy: .public)': \(error)")
        }
    }

    /// Foci's environment without the terminal session it may have been started from (`open Foci.app` in a
    /// Herdr pane passes that pane's variables on): with `HERDR_ENV`, `herdr` in a launched kitty refuses to
    /// start, as nested, and the window closes at once.
    static func inheritable(_ environment: [String: String]) -> [String: String] {
        let prefixes = ["HERDR_", "KITTY_", "TMUX", "ZELLIJ", "TERM_PROGRAM", "TERM_SESSION_ID", "ITERM_"]
        return environment.filter { key, _ in !prefixes.contains { key.hasPrefix($0) } }
    }
}

import FociCore
import Foundation
import os

/// Runs commands in a login shell so PATH matches the terminal (Homebrew, ~/.local/bin, ...).
@MainActor
public final class ShellLauncher: Launcher {
    private let log = Logger(subsystem: "dev.foci", category: "launch")

    public init() {}

    public func run(_ shellCommand: String, environment: [String: String]) {
        let env = Self.inheritable(ProcessInfo.processInfo.environment).merging(environment) { _, new in new }
        do {
            let pid = try Self.spawnDisclaimed(
                "/bin/zsh", ["-lc", shellCommand], environment: env,
                directory: FileManager.default.homeDirectoryForCurrentUser.path)
            // Reap it, so it doesn't stay a zombie.
            DispatchQueue.global(qos: .utility).async {
                var status: Int32 = 0
                while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
            }
            log.info("launched: \(shellCommand, privacy: .public)")
        } catch {
            log.error("can't run '\(shellCommand, privacy: .public)': \(error)")
        }
    }

    /// Starts `path` as its own responsible process. Otherwise macOS holds Foci responsible for everything a
    /// launched app does (a kitty started by Foci, the shells in it, a Cursor started by its CLI): their file
    /// access asks "Foci would like to access files in your Documents folder" and the like, again and again.
    /// Terminals (Terminal, iTerm2) disclaim their children the same way.
    static func spawnDisclaimed(
        _ path: String, _ arguments: [String], environment: [String: String], directory: String
    ) throws -> pid_t {
        var attr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // Only the standard streams below reach the child, not Foci's socket or lock file.
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        var all = sigset_t(), none = sigset_t()
        sigfillset(&all)
        sigemptyset(&none)
        posix_spawnattr_setsigdefault(&attr, &all)
        posix_spawnattr_setsigmask(&attr, &none)
        if let disclaim = setDisclaim { _ = disclaim(&attr, 1) }

        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addchdir_np(&actions, directory)

        let argv = ([path] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, path, &actions, &attr, argv, envp)
        guard rc == 0 else { throw POSIXError(POSIXErrorCode(rawValue: rc) ?? .EINVAL) }
        return pid
    }

    /// `responsibility_spawnattrs_setdisclaim`: private, but in libSystem since macOS 10.14.
    private typealias SetDisclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
    private static let setDisclaim: SetDisclaim? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim")
        else { return nil }
        return unsafeBitCast(sym, to: SetDisclaim.self)
    }()

    /// Foci's environment without the terminal session it may have been started from (`open Foci.app` in a
    /// Herdr pane passes that pane's variables on): with `HERDR_ENV`, `herdr` in a launched kitty refuses to
    /// start, as nested, and the window closes at once.
    static func inheritable(_ environment: [String: String]) -> [String: String] {
        let prefixes = ["HERDR_", "KITTY_", "TMUX", "ZELLIJ", "TERM_PROGRAM", "TERM_SESSION_ID", "ITERM_"]
        return environment.filter { key, _ in !prefixes.contains { key.hasPrefix($0) } }
    }
}

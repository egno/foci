import Foundation

/// Where Foci keeps its files. The environment variable `FOCI_HOME` (for tests) moves all of them into one
/// directory: `config.toml`, `state.json`, `foci.sock`, `foci.lock`. Without it the config is in
/// `~/.config/foci` and the rest in `~/Library/Application Support/Foci`.
public enum FociPaths {
    public static func home(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        guard let path = environment["FOCI_HOME"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    public static func config(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        home(environment)?.appending(path: "config.toml")
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/foci/config.toml")
    }

    /// State, socket and lock file.
    public static func support(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        home(environment) ?? URL.applicationSupportDirectory.appending(path: "Foci")
    }

    public static var isOverridden: Bool { home() != nil }
}

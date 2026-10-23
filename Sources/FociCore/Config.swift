import Foundation

public struct Config: Equatable, Sendable {
    /// Gap in points around and between windows.
    public var gap: Double = 0
    /// Workspace name → display spec, see `DisplaySpec`. Every workspace lives on exactly one display.
    public var workspaces: [String: DisplaySpec] = [:]
    /// Initial layout per workspace; `defaultLayout` for the rest. `layout` commands override both at runtime.
    public var workspaceLayouts: [String: Layout] = [:]
    public var defaultLayout = Layout()
    public var apps: [String: AppDef] = [:]
    /// Ordered: defines `project next|prev`.
    public var projects: [ProjectDef] = []
    /// Mode name → key combo → command script.
    public var modes: [String: [KeyCombo: String]] = ["main": [:]]

    public init() {}

    public func project(_ name: String) -> ProjectDef? { projects.first { $0.name == name } }

    /// Problems that don't prevent loading but make the config ambiguous.
    public func validate() -> [String] {
        var errors: [String] = []
        var seen = Set<String>()
        for p in projects {
            if !seen.insert(p.name).inserted { errors.append("project '\(p.name)' is declared twice") }
            for ref in p.apps where apps[ref.app] == nil {
                errors.append("project '\(p.name)' references unknown app '\(ref.app)'")
            }
        }
        for (id, app) in apps where !app.isPerProject {
            let users = projects.filter { $0.apps.contains { $0.app == id } }
            if users.count > 1 {
                errors.append(
                    "app '\(id)' has no {project} placeholder but is used by several projects: "
                        + users.map(\.name).joined(separator: ", "))
            }
        }
        if modes["main"] == nil { errors.append("mode 'main' is missing") }
        return errors
    }
}

public enum DisplaySpec: Equatable, Sendable {
    /// The display with the menu bar.
    case main
    /// The first display that isn't main.
    case secondary
    /// 1-based index, ordered left to right.
    case index(Int)
    /// Case-insensitive substring of the display name.
    case name(String)

    public init(parsing s: String) {
        switch s.lowercased() {
        case "main", "primary": self = .main
        case "secondary": self = .secondary
        default: self = Int(s).map(DisplaySpec.index) ?? .name(s)
        }
    }

    public func resolve(in displays: [Display]) -> Display? {
        let sorted = displays.sorted { $0.frame.x < $1.frame.x }
        switch self {
        case .main: return displays.first(where: \.isMain)
        case .secondary: return sorted.first { !$0.isMain }
        case .index(let i): return sorted.indices.contains(i - 1) ? sorted[i - 1] : nil
        case .name(let n): return displays.first { $0.name.localizedCaseInsensitiveContains(n) }
        }
    }
}

public enum NewWindowPolicy: String, Equatable, Sendable {
    /// New windows matching no link rule stay unlinked.
    case unlinked
    /// New windows matching no link rule are linked to the active project (if it uses the app).
    case activeProject = "active-project"
}

/// `[apps.<id>]`: how to recognize an app's windows and how to start it.
public struct AppDef: Equatable, Sendable {
    public var id: String
    public var bundleID: String?
    /// Regex over the process command line. `{project}` is replaced by the project name.
    public var args: String?
    /// Regex over the window title. `{project}` is replaced by the project name.
    public var title: String?
    /// Default workspace for the app's windows.
    public var workspace: String?
    /// Shell command starting a window for a project. `{project}` and `{open}` are substituted.
    public var launch: String?
    /// Shell command starting the app outside any project.
    public var globalLaunch: String?
    public var newWindows: NewWindowPolicy = .unlinked
    public var floating: Bool = false
    /// false: Foci ignores the app's windows completely.
    public var manage: Bool = true

    public init(id: String, bundleID: String? = nil) {
        self.id = id; self.bundleID = bundleID
    }

    /// Each project gets its own instance / windows, told apart by `{project}` in a pattern.
    public var isPerProject: Bool {
        [args, title].contains { $0?.contains("{project}") == true }
    }
}

public struct ProjectAppRef: Equatable, Sendable {
    public var app: String
    /// Launch the app when switching to its workspace and the project has no window of it.
    public var autostart: Bool = true
    /// Overrides `AppDef.workspace` for this project.
    public var workspace: String?
    /// Items substituted into `{open}`, e.g. repo folders.
    public var open: [String] = []

    public init(app: String, autostart: Bool = true, workspace: String? = nil, open: [String] = []) {
        self.app = app; self.autostart = autostart; self.workspace = workspace; self.open = open
    }
}

public struct ProjectDef: Equatable, Sendable {
    public var name: String
    public var apps: [ProjectAppRef]

    public init(name: String, apps: [ProjectAppRef] = []) {
        self.name = name; self.apps = apps
    }

    public func ref(_ app: String) -> ProjectAppRef? { apps.first { $0.app == app } }
}

public enum Modifier: String, CaseIterable, Hashable, Sendable, Comparable {
    case cmd, ctrl, alt, shift
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// e.g. `ctrl-shift-p`, `f20`.
public struct KeyCombo: Hashable, Sendable, CustomStringConvertible {
    public let modifiers: Set<Modifier>
    public let key: String

    public init(modifiers: Set<Modifier>, key: String) {
        self.modifiers = modifiers; self.key = key
    }

    public init?(parsing s: String) {
        var parts = s.lowercased().split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        // "alt-minus" is fine; a literal "-" key is spelled "minus".
        guard let key = parts.popLast(), !key.isEmpty else { return nil }
        var mods = Set<Modifier>()
        for p in parts {
            switch p {
            case "cmd", "command": mods.insert(.cmd)
            case "ctrl", "control": mods.insert(.ctrl)
            case "alt", "option", "opt": mods.insert(.alt)
            case "shift": mods.insert(.shift)
            default: return nil
            }
        }
        self.init(modifiers: mods, key: key)
    }

    public var description: String { (modifiers.sorted().map(\.rawValue) + [key]).joined(separator: "-") }
}

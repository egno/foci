import Foundation

public struct Config: Equatable, Sendable {
    /// Register Foci as a login item.
    public var startAtLogin = false
    public var menuBarStyle: MenuBarStyle = .i3
    /// Gap in points around and between windows.
    public var gap: Double = 0
    /// Maximized windows as an accordion: points of the windows behind the focused one shown at its sides.
    public var accordionPadding: Double = 30
    /// Workspace name → display spec, see `DisplaySpec`. Every workspace lives on exactly one display.
    public var workspaces: [String: DisplaySpec] = [:]
    /// Initial layout per workspace; `defaultLayout` for the rest. `layout` commands override both at runtime.
    public var workspaceLayouts: [String: Layout] = [:]
    public var defaultLayout = Layout()
    public var apps: [String: AppDef] = [:]
    /// App that opens links from outside any project, or from a project that uses no app with `open-url`.
    public var browser: String?
    /// Ordered: defines `project next|prev`.
    public var projects: [ProjectDef] = []
    /// Keys the name `leader` stands for in bindings: binding `leader` binds each of them.
    public var leaderKeys: [KeyCombo] = []
    /// Mode name → key combo → command script.
    public var modes: [String: [KeyCombo: String]] = ["main": [:]]
    /// Mode name → key combo → label shown in the key hints instead of the script.
    public var bindingLabels: [String: [KeyCombo: String]] = [:]
    /// Mode name → label of the group, shown as `+label` for keys that enter the mode.
    public var modeLabels: [String: String] = [:]
    /// Mode name → key → what the `{project}` binding it came from does without the project (`project`,
    /// `link --follow`): key hints show those keys as one row.
    public var projectKeys: [String: [KeyCombo: String]] = [:]
    /// Modes that stay active after a key; any other mode but `main` returns to `main` after one key.
    public var stickyModes: Set<String> = []
    /// Mode name → keys that repeat, like Emacs's repeat-mode: after one of them acts, the mode stays open with
    /// only its repeat keys, so `j j j` needs one leader.
    public var repeatKeys: [String: Set<KeyCombo>] = [:]
    /// Seconds a submenu waits for a key before it closes; 0 = no limit.
    public var leaderTimeout: Double = 5
    /// Seconds the repeat keys stay active after the last one.
    public var repeatTimeout: Double = 1
    /// Windows `focus-back` can go back to.
    public var focusHistory = 10
    /// Seconds a `hold-` key must be held down to act; a shorter press types the key.
    public var holdDelay: Double = 0.25
    /// Popup listing the next keys when a mode other than `main` waits for a key, like which-key.
    public var keyHints = true
    /// Seconds without a key press before the hints appear.
    public var keyHintsDelay: Double = 0.3

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
        if let b = browser {
            if apps[b] == nil {
                errors.append("browser: unknown app '\(b)'")
            } else if apps[b]?.globalOpenURL == nil {
                errors.append("browser: app '\(b)' has no global-open-url command")
            }
        }
        if modes["main"] == nil { errors.append("mode 'main' is missing") }
        return errors
    }
}

/// The menu bar label, after AeroSpace's experimental UI.
public enum MenuBarStyle: String, CaseIterable, Equatable, Sendable {
    /// `BIL · [w] x`
    case text
    /// The project, then the workspace shown on each display as a lettered square; the focused one filled.
    case squares
    /// Like `squares`, plus the hidden workspaces that have windows in the active project, dimmed.
    case i3
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
    /// Shell command opening a link for a project, run after focusing the project's window of the app.
    /// `{url}` and `{project}` are substituted. Makes the app the project's browser.
    public var openURL: String?
    /// Shell command opening a link outside any project, see `Config.browser`. `{url}` is substituted.
    public var globalOpenURL: String?
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
    /// The key `{project}` in a binding stands for; the first letter of the name unless set.
    public var key: String

    public init(name: String, apps: [ProjectAppRef] = [], key: String? = nil) {
        self.name = name; self.apps = apps; self.key = key ?? String(name.prefix(1)).lowercased()
    }

    public func ref(_ app: String) -> ProjectAppRef? { apps.first { $0.app == app } }
}

public enum Modifier: String, CaseIterable, Hashable, Sendable, Comparable {
    case cmd, ctrl, alt, shift
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// e.g. `ctrl-shift-p`, `f20`, or a modifier key tapped alone: `right-cmd`.
public struct KeyCombo: Hashable, Sendable, CustomStringConvertible {
    /// Stands for all of `Config.leaderKeys` in key hints.
    public static let leader = KeyCombo(modifiers: [], key: "leader")


    /// Modifier keys that act as a key when pressed and released alone, like Karabiner's `to_if_alone`.
    public static let tapKeys: Set<String> = [
        "left-cmd", "right-cmd", "left-alt", "right-alt", "left-ctrl", "right-ctrl", "left-shift", "right-shift",
    ]

    public let modifiers: Set<Modifier>
    public let key: String

    public init(modifiers: Set<Modifier>, key: String) {
        self.modifiers = modifiers; self.key = key
    }

    /// A plain key held down past `Config.holdDelay` acts as this key; tapped, it still types (`hold-space`).
    public static let holdPrefix = "hold-"

    /// The plain key of a `hold-` key.
    public var heldKey: String? { key.hasPrefix(Self.holdPrefix) ? String(key.dropFirst(Self.holdPrefix.count)) : nil }

    public init?(parsing s: String) {
        if Self.tapKeys.contains(s.lowercased()) {
            self.init(modifiers: [], key: s.lowercased())
            return
        }
        if s.lowercased().hasPrefix(Self.holdPrefix) {
            let key = String(s.lowercased().dropFirst(Self.holdPrefix.count))
            guard !key.isEmpty, !key.contains("-") else { return nil }
            self.init(modifiers: [], key: Self.holdPrefix + key)
            return
        }
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

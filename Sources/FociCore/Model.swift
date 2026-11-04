import Foundation

/// CGWindowID of a window. Stable while the owning process runs.
public struct WindowID: Hashable, Comparable, Codable, Sendable, CustomStringConvertible, CodingKeyRepresentable {
    public let raw: UInt32
    public init(_ raw: UInt32) { self.raw = raw }
    public var description: String { String(raw) }
    public static func < (a: Self, b: Self) -> Bool { a.raw < b.raw }

    public init(from decoder: Decoder) throws { raw = try decoder.singleValueContainer().decode(UInt32.self) }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }
    public var codingKey: CodingKey { AnyKey(description) }
    public init?<T: CodingKey>(codingKey: T) {
        guard let raw = UInt32(codingKey.stringValue) else { return nil }
        self.raw = raw
    }
}

/// CGDirectDisplayID of a display.
public struct DisplayID: Hashable, Codable, Sendable, CustomStringConvertible, CodingKeyRepresentable {
    public let raw: UInt32
    public init(_ raw: UInt32) { self.raw = raw }
    public var description: String { String(raw) }

    public init(from decoder: Decoder) throws { raw = try decoder.singleValueContainer().decode(UInt32.self) }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }
    public var codingKey: CodingKey { AnyKey(description) }
    public init?<T: CodingKey>(codingKey: T) {
        guard let raw = UInt32(codingKey.stringValue) else { return nil }
        self.raw = raw
    }
}

struct AnyKey: CodingKey {
    let stringValue: String
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
}

/// Rectangle in Accessibility coordinates: origin at the top-left corner of the main display, y grows down.
public struct Rect: Equatable, Codable, Sendable, CustomStringConvertible {
    public var x, y, width, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var center: (x: Double, y: Double) { (x + width / 2, y + height / 2) }
    public var description: String { "(\(Int(x)),\(Int(y)) \(Int(width))x\(Int(height)))" }

    public func contains(x px: Double, y py: Double) -> Bool { px >= x && px < maxX && py >= y && py < maxY }
    /// Area of the overlap with another rectangle, 0 if they don't overlap.
    public func overlapArea(_ o: Rect) -> Double {
        max(0, min(maxX, o.maxX) - max(x, o.x)) * max(0, min(maxY, o.maxY) - max(y, o.y))
    }
    public func insetBy(_ d: Double) -> Rect { Rect(x: x + d, y: y + d, width: width - 2 * d, height: height - 2 * d) }
    public func isClose(to other: Rect, tolerance: Double = 1) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}

public struct Display: Equatable, Sendable {
    public let id: DisplayID
    public let name: String
    /// Full frame and the frame without menu bar and Dock, both in Accessibility coordinates.
    public let frame: Rect
    public let visibleFrame: Rect
    /// The display with the menu bar.
    public let isMain: Bool
    /// The laptop's own screen.
    public let isBuiltIn: Bool

    public init(id: DisplayID, name: String, frame: Rect, visibleFrame: Rect, isMain: Bool, isBuiltIn: Bool = false) {
        self.id = id; self.name = name; self.frame = frame; self.visibleFrame = visibleFrame; self.isMain = isMain
        self.isBuiltIn = isBuiltIn
    }

    /// The names Foci shows and matches: `built-in` for the laptop's screen, `ext 1`...`ext N` for the others,
    /// left to right (then top to bottom). Unlike the model name (`name`) they tell two monitors of one model apart.
    public static func labels(_ displays: [Display]) -> [DisplayID: String] {
        var result: [DisplayID: String] = [:]
        var n = 0
        for d in spatial(displays) {
            if d.isBuiltIn {
                result[d.id] = "built-in"
            } else {
                n += 1
                result[d.id] = "ext \(n)"
            }
        }
        return result
    }

    /// A display named in the config or a command: `main`, its label (`built-in`, `ext 2`; `ext2` and `ext-2`
    /// too, so it fits in a command), or part of its model name.
    func matches(_ entry: String, label: String?) -> Bool {
        func normalized(_ s: String) -> String { s.lowercased().filter { !" -_".contains($0) } }
        let e = entry.lowercased()
        if e == "main" || e == "primary" { return isMain }
        if let label, normalized(entry) == normalized(label) { return true }
        // 'built-in' names the laptop's screen, not a monitor whose model name contains it.
        if normalized(entry) == "builtin" { return isBuiltIn }
        return name.localizedCaseInsensitiveContains(entry)
    }

    static func spatial(_ displays: [Display]) -> [Display] {
        displays.sorted { ($0.frame.x, $0.frame.y, $0.id.raw) < ($1.frame.x, $1.frame.y, $1.id.raw) }
    }

    /// The one display order everywhere (display numbers, next/prev, menu bar): the displays `order` names
    /// first, in its order, then the rest left to right, then top to bottom for displays stacked above each
    /// other. An entry of `order` names a display (see `matches`: `main`, `built-in`, `ext 2`, part of the model
    /// name); it takes the leftmost display it matches that no earlier entry took.
    public static func ordered(_ displays: [Display], by order: [String] = []) -> [Display] {
        var rest = spatial(displays)
        let labels = labels(displays)
        var named: [Display] = []
        for entry in order {
            if let i = rest.firstIndex(where: { $0.matches(entry, label: labels[$0.id]) }) {
                named.append(rest.remove(at: i))
            }
        }
        return named + rest
    }

    /// The nearest display on that side: one wholly beyond that edge (displays don't overlap), overlapping this
    /// one across the direction first (right next to it rather than diagonal), then the closest. nil at the edge.
    public func neighbour(_ side: Side, in displays: [Display]) -> Display? {
        let f = frame, c = f.center
        func gap(_ d: Display) -> Double? {
            let o = d.frame
            let g: Double
            switch side {
            case .left: g = f.x - o.maxX
            case .right: g = o.x - f.maxX
            case .up: g = f.y - o.maxY
            case .down: g = o.y - f.maxY
            }
            return g >= -1 ? max(0, g) : nil
        }
        func overlapsAcross(_ d: Display) -> Bool {
            switch side {
            case .left, .right: return d.frame.y < f.maxY && f.y < d.frame.maxY
            case .up, .down: return d.frame.x < f.maxX && f.x < d.frame.maxX
            }
        }
        func across(_ d: Display) -> Double {
            let o = d.frame.center
            return side == .left || side == .right ? abs(o.y - c.y) : abs(o.x - c.x)
        }
        return displays.compactMap { d in d.id == id ? nil : gap(d).map { (d, $0) } }
            .min { (overlapsAcross($0.0) ? 0 : 1, $0.1, across($0.0)) < (overlapsAcross($1.0) ? 0 : 1, $1.1, across($1.0)) }?
            .0
    }
}

public enum Side: String, Equatable, Sendable, CaseIterable {
    case left, right, up, down
}

/// A standard window as reported by the OS.
public struct WindowFacts: Equatable, Sendable {
    public let id: WindowID
    public let pid: Int32
    public let bundleID: String?
    public let appName: String
    /// The process command line (argv joined by spaces).
    public let appArgs: String
    public var title: String
    public var frame: Rect
    /// Minimized, app hidden (Cmd-H) or native fullscreen: Foci keeps its record but doesn't move it.
    public var isFrozen: Bool

    public init(
        id: WindowID, pid: Int32, bundleID: String?, appName: String, appArgs: String, title: String, frame: Rect,
        isFrozen: Bool = false
    ) {
        self.id = id; self.pid = pid; self.bundleID = bundleID; self.appName = appName
        self.appArgs = appArgs; self.title = title; self.frame = frame; self.isFrozen = isFrozen
    }
}

public enum LayoutKind: String, Codable, Sendable {
    /// Every window fills the display; focus cycles through them.
    case maximized
    /// Windows side by side (or stacked), sized by weight.
    case tiles
}

public enum Orientation: String, Codable, Sendable {
    /// Side by side on landscape displays, stacked on portrait ones.
    case auto, horizontal, vertical
}

public struct Layout: Equatable, Codable, Sendable {
    public var kind: LayoutKind
    public var orientation: Orientation

    public init(_ kind: LayoutKind = .maximized, orientation: Orientation = .auto) {
        self.kind = kind; self.orientation = orientation
    }
}

/// What Foci knows about a managed window.
public struct WindowRecord: Equatable, Codable, Sendable {
    /// The project the window is linked to; nil = unlinked (never touched by project switching).
    public var owner: String?
    public var workspace: String
    /// The `[apps.<id>]` definition the window matched, if any.
    public var app: String?
    public var floating: Bool = false
    /// The owner was set by hand: link rules no longer apply to this window.
    public var manual: Bool = false
    /// Last on-screen frame of a floating window.
    public var floatingFrame: Rect?
    /// Order within the workspace: window cycling and tile order. Starts as creation order.
    public var seq: Int = 0
    /// Relative tile size.
    public var weight: Double = 1

    public init(owner: String?, workspace: String, app: String? = nil, floating: Bool = false, seq: Int = 0) {
        self.owner = owner; self.workspace = workspace; self.app = app; self.floating = floating; self.seq = seq
    }

    // Missing keys take their defaults, so state files from older versions stay readable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        owner = try c.decodeIfPresent(String.self, forKey: .owner)
        workspace = try c.decode(String.self, forKey: .workspace)
        app = try c.decodeIfPresent(String.self, forKey: .app)
        floating = try c.decodeIfPresent(Bool.self, forKey: .floating) ?? false
        manual = try c.decodeIfPresent(Bool.self, forKey: .manual) ?? false
        floatingFrame = try c.decodeIfPresent(Rect.self, forKey: .floatingFrame)
        seq = try c.decodeIfPresent(Int.self, forKey: .seq) ?? 0
        weight = try c.decodeIfPresent(Double.self, forKey: .weight) ?? 1
    }
}

/// `nil` inside means "no project".
public struct ProjectSlot: Equatable, Codable, Sendable {
    public var name: String?
    public init(_ name: String?) { self.name = name }
}

/// What a project showed when it was last active.
public struct ProjectView: Equatable, Codable, Sendable {
    /// The workspace shown on each display.
    public var activeWorkspace: [DisplayID: String]
    public var focusedWorkspace: String?

    public init(activeWorkspace: [DisplayID: String], focusedWorkspace: String?) {
        self.activeWorkspace = activeWorkspace; self.focusedWorkspace = focusedWorkspace
    }
}

/// Everything Foci persists between runs.
public struct State: Equatable, Codable, Sendable {
    public var activeProject: String?
    public var previousProject: ProjectSlot?
    /// Workspace → display, for workspaces moved at runtime or created ad hoc. Overrides the config.
    public var workspaceDisplay: [String: DisplayID] = [:]
    /// The workspace shown on each display.
    public var activeWorkspace: [DisplayID: String] = [:]
    /// Workspaces each display showed, most recent first: what a reconnected display shows again.
    public var displayHistory: [DisplayID: [String]] = [:]
    public var focusedWorkspace: String?
    public var previousWorkspace: String?
    public var windows: [WindowID: WindowRecord] = [:]
    /// Last focused window per "project|workspace".
    public var lastFocused: [String: WindowID] = [:]
    /// Layout chosen at runtime per "project|workspace". Overrides the config.
    public var layouts: [String: Layout] = [:]
    /// What each project ("" = no project) showed when it was last active; restored when it becomes active again.
    public var projectViews: [String: ProjectView] = [:]
    public var nextSeq: Int = 0

    public init() {}

    // Missing keys take their defaults, so state files from older versions stay readable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeProject = try c.decodeIfPresent(String.self, forKey: .activeProject)
        previousProject = try c.decodeIfPresent(ProjectSlot.self, forKey: .previousProject)
        workspaceDisplay = try c.decodeIfPresent([String: DisplayID].self, forKey: .workspaceDisplay) ?? [:]
        activeWorkspace = try c.decodeIfPresent([DisplayID: String].self, forKey: .activeWorkspace) ?? [:]
        displayHistory = try c.decodeIfPresent([DisplayID: [String]].self, forKey: .displayHistory) ?? [:]
        focusedWorkspace = try c.decodeIfPresent(String.self, forKey: .focusedWorkspace)
        previousWorkspace = try c.decodeIfPresent(String.self, forKey: .previousWorkspace)
        windows = try c.decodeIfPresent([WindowID: WindowRecord].self, forKey: .windows) ?? [:]
        lastFocused = try c.decodeIfPresent([String: WindowID].self, forKey: .lastFocused) ?? [:]
        layouts = try c.decodeIfPresent([String: Layout].self, forKey: .layouts) ?? [:]
        projectViews = try c.decodeIfPresent([String: ProjectView].self, forKey: .projectViews) ?? [:]
        nextSeq = try c.decodeIfPresent(Int.self, forKey: .nextSeq) ?? 0
    }

    static func focusKey(project: String?, workspace: String) -> String { "\(project ?? "")|\(workspace)" }
}

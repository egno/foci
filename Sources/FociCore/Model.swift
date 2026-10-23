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

    public init(id: DisplayID, name: String, frame: Rect, visibleFrame: Rect, isMain: Bool) {
        self.id = id; self.name = name; self.frame = frame; self.visibleFrame = visibleFrame; self.isMain = isMain
    }
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
    /// Creation order, used for stable window cycling.
    public var seq: Int = 0

    public init(owner: String?, workspace: String, app: String? = nil, floating: Bool = false, seq: Int = 0) {
        self.owner = owner; self.workspace = workspace; self.app = app; self.floating = floating; self.seq = seq
    }
}

/// `nil` inside means "no project".
public struct ProjectSlot: Equatable, Codable, Sendable {
    public var name: String?
    public init(_ name: String?) { self.name = name }
}

/// Everything Foci persists between runs.
public struct State: Equatable, Codable, Sendable {
    public var activeProject: String?
    public var previousProject: ProjectSlot?
    /// Workspace → display, for workspaces moved at runtime or created ad hoc. Overrides the config.
    public var workspaceDisplay: [String: DisplayID] = [:]
    /// The workspace shown on each display.
    public var activeWorkspace: [DisplayID: String] = [:]
    public var focusedWorkspace: String?
    public var previousWorkspace: String?
    public var windows: [WindowID: WindowRecord] = [:]
    /// Last focused window per "project|workspace".
    public var lastFocused: [String: WindowID] = [:]
    public var nextSeq: Int = 0

    public init() {}

    static func focusKey(project: String?, workspace: String) -> String { "\(project ?? "")|\(workspace)" }
}

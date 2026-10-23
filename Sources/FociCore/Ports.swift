import Foundation

/// The OS window server, as seen by the engine.
@MainActor
public protocol WindowSystem: AnyObject {
    func displays() -> [Display]
    /// All manageable windows of all regular apps (standard, not minimized, not native fullscreen).
    func windows() -> [WindowFacts]
    func focusedWindow() -> WindowID?
    func setFrame(_ id: WindowID, _ frame: Rect)
    func focus(_ id: WindowID)
}

@MainActor
public protocol Launcher: AnyObject {
    func run(_ shellCommand: String, environment: [String: String])
}

@MainActor
public protocol StateStore: AnyObject {
    func load() -> State?
    func save(_ state: State)
}

@MainActor
public protocol ConfigSource: AnyObject {
    func load() throws -> Config
}

public protocol Clock: Sendable {
    func now() -> Date
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}

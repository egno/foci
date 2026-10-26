import Foundation
@testable import FociCore

@MainActor
final class FakeWindowSystem: WindowSystem {
    var displayList: [Display]
    var windowList: [WindowFacts] = []
    var focused: WindowID?
    var focusCalls: [WindowID] = []

    init(displays: [Display] = [.left, .right]) { displayList = displays }

    func displays() -> [Display] { displayList }
    func windows() -> [WindowFacts] { windowList }
    func focusedWindow() -> WindowID? { focused }
    func setFrame(_ id: WindowID, _ frame: Rect) {
        if let i = windowList.firstIndex(where: { $0.id == id }) { windowList[i].frame = frame }
    }
    func focus(_ id: WindowID) {
        focused = id
        focusCalls.append(id)
    }

    @discardableResult
    func open(
        _ id: UInt32, bundle: String, args: String = "", title: String = "", pid: Int32 = 1,
        frame: Rect = Rect(x: 100, y: 100, width: 800, height: 600)
    ) -> WindowID {
        windowList.append(
            WindowFacts(
                id: WindowID(id), pid: pid, bundleID: bundle, appName: bundle, appArgs: args, title: title,
                frame: frame))
        return WindowID(id)
    }

    func frame(_ id: UInt32) -> Rect { windowList.first { $0.id == WindowID(id) }!.frame }
}

@MainActor
final class FakeLauncher: Launcher {
    var commands: [(String, [String: String])] = []
    func run(_ shellCommand: String, environment: [String: String]) { commands.append((shellCommand, environment)) }
}

@MainActor
final class InMemoryStore: StateStore {
    var state: State?
    func load() -> State? { state }
    func save(_ state: State) { self.state = state }
}

@MainActor
final class FixedConfigSource: ConfigSource {
    var config: Config
    init(_ config: Config) { self.config = config }
    func load() throws -> Config { config }
}

final class FakeClock: Clock, @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 0)
    func now() -> Date { date }
}

extension Display {
    /// Main display on the left, laptop on the right.
    static let left = Display(
        id: DisplayID(1), name: "LG HDR 4K", frame: Rect(x: 0, y: 0, width: 2560, height: 1440),
        visibleFrame: Rect(x: 0, y: 25, width: 2560, height: 1415), isMain: true)
    static let right = Display(
        id: DisplayID(2), name: "Color LCD", frame: Rect(x: 2560, y: 0, width: 1512, height: 982),
        visibleFrame: Rect(x: 2560, y: 0, width: 1512, height: 982), isMain: false)
}

extension Config {
    /// Chrome windows are linked by title, kitty instances by args. Slack is unlinked on workspace s.
    static var sample: Config {
        var c = Config()
        c.accordionPadding = 0  // maximized means full size; AccordionTests set it
        c.workspaces = ["w": .main, "c": .main, "x": .secondary, "s": .secondary]
        var chrome = AppDef(id: "chrome", bundleID: "com.google.Chrome")
        chrome.title = "^{project} - Google Chrome$"
        chrome.workspace = "w"
        chrome.launch = "open -na 'Google Chrome' --args --new-window"
        chrome.globalLaunch = "open -a 'Google Chrome'"
        var kitty = AppDef(id: "kitty", bundleID: "net.kovidgoyal.kitty")
        kitty.args = "--instance-group {project}( |$)"
        kitty.workspace = "x"
        kitty.launch = "kitty --instance-group {project}"
        var cursor = AppDef(id: "cursor", bundleID: "com.todesktop.cursor")
        cursor.args = "--user-data-dir .*/{project}( |$)"
        cursor.workspace = "c"
        cursor.launch = "cursor --user-data-dir ~/.cursor-projects/{project} {open}"
        var slack = AppDef(id: "slack", bundleID: "com.tinyspeck.slackmacgap")
        slack.workspace = "s"
        c.apps = ["chrome": chrome, "kitty": kitty, "cursor": cursor, "slack": slack]
        c.projects = [
            ProjectDef(name: "bil", apps: [
                ProjectAppRef(app: "chrome", autostart: false), ProjectAppRef(app: "kitty", autostart: false),
                ProjectAppRef(app: "cursor", open: ["~/src/bil api"]),
            ]),
            ProjectDef(name: "iam", apps: [
                ProjectAppRef(app: "chrome", autostart: false), ProjectAppRef(app: "kitty", autostart: false),
            ]),
        ]
        return c
    }
}

@MainActor
struct Harness {
    let ws: FakeWindowSystem
    let launcher = FakeLauncher()
    let store = InMemoryStore()
    let clock = FakeClock()
    let engine: Engine

    init(config: Config = .sample, ws: FakeWindowSystem = FakeWindowSystem(), state: State? = nil) {
        self.ws = ws
        store.state = state
        engine = Engine(
            config: config, windowSystem: ws, launcher: launcher, store: store,
            configSource: FixedConfigSource(config), clock: clock)
    }

    func record(_ id: UInt32) -> WindowRecord? { engine.state.windows[WindowID(id)] }
    func visible(_ id: UInt32) -> Bool { engine.isVisible(record(id)!) }
}

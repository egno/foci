import Foundation

/// A `foci <args>` invocation, as sent by the CLI client to the running app.
public enum CLIRequest: Equatable, Sendable {
    public struct WindowFilter: Equatable, Sendable {
        public enum Owner: Equatable, Sendable { case any, project(String), unlinked, active }
        public var owner: Owner = .any
        public var workspace: String?
        public var visibleOnly = false
        public var pid: Int32?
        public init() {}
    }

    case run(script: String, window: WindowID?)
    /// Open a link in the browser of the client's project, see `Engine.openURL`.
    case open(url: String)
    case status(json: Bool)
    case listWindows(WindowFilter, json: Bool)
    case listWorkspaces(json: Bool)
    case listProjects(json: Bool)
    case subscribe
    case help

    public static let usage = """
        usage: foci                          start the app (normally via Foci.app)
               foci <command script>         e.g. foci project bil; foci 'workspace w; layout tiles'
               foci run [--window <id>] <script>
               foci open <url>               open a link in this terminal's project browser
               foci status [--json]
               foci list-windows [--json] [--project <name> | --unlinked | --active]
                                 [--workspace <name>] [--visible] [--pid <pid>]
               foci list-workspaces [--json]
               foci list-projects [--json]
               foci subscribe                one JSON status line per change

        commands: project <name>|--none|next|prev, project-back-and-forth,
                  workspace <name>|next|prev, workspace-back-and-forth,
                  move-to-workspace [--follow] <name>, move-to-display [--follow] next|prev,
                  move-workspace-to-display next|prev,
                  focus-display next|prev, focus next|prev, move next|prev,
                  layout tiles|maximized|toggle|toggle-orientation, resize +N|-N, balance,
                  link <project>|--active, unlink, float, reveal, launch <app>, mode <name>,
                  reload-config, exec <shell command>
        """

    public struct UsageError: Error, Equatable, CustomStringConvertible {
        public let description: String
    }

    public static func parse(_ args: [String]) throws -> CLIRequest {
        guard let first = args.first else { return .help }
        var rest = Array(args.dropFirst())

        func flag(_ name: String) -> Bool {
            guard let i = rest.firstIndex(of: name) else { return false }
            rest.remove(at: i)
            return true
        }
        func option(_ name: String) throws -> String? {
            guard let i = rest.firstIndex(of: name) else { return nil }
            guard i + 1 < rest.count else { throw UsageError(description: "\(name) needs a value") }
            let v = rest[i + 1]
            rest.removeSubrange(i...(i + 1))
            return v
        }
        func done() throws {
            if let extra = rest.first { throw UsageError(description: "unexpected argument '\(extra)'") }
        }

        switch first {
        case "help", "--help", "-h":
            return .help
        case "run":
            let window = try option("--window").map { v -> WindowID in
                guard let raw = UInt32(v) else { throw UsageError(description: "bad window id '\(v)'") }
                return WindowID(raw)
            }
            guard !rest.isEmpty else { throw UsageError(description: "run: missing command script") }
            return .run(script: rest.joined(separator: " "), window: window)
        case "open":
            guard rest.count == 1 else { throw UsageError(description: "usage: foci open <url>") }
            return .open(url: rest[0])
        case "status":
            let json = flag("--json")
            try done()
            return .status(json: json)
        case "list-windows":
            var f = WindowFilter()
            let json = flag("--json")
            f.visibleOnly = flag("--visible")
            if let p = try option("--project") { f.owner = .project(p) }
            if flag("--unlinked") { f.owner = .unlinked }
            if flag("--active") { f.owner = .active }
            f.workspace = try option("--workspace")
            if let p = try option("--pid") {
                guard let pid = Int32(p) else { throw UsageError(description: "bad pid '\(p)'") }
                f.pid = pid
            }
            try done()
            return .listWindows(f, json: json)
        case "list-workspaces":
            let json = flag("--json")
            try done()
            return .listWorkspaces(json: json)
        case "list-projects":
            let json = flag("--json")
            try done()
            return .listProjects(json: json)
        case "subscribe":
            try done()
            return .subscribe
        default:
            // `foci project bil` == `foci run project bil`. Validate here for a usage error instead of a no-op.
            let script = args.joined(separator: " ")
            do { _ = try Command.parseScript(script) } catch { throw UsageError(description: "\(error)") }
            return .run(script: script, window: nil)
        }
    }
}

public struct CLIResponse: Equatable, Codable, Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(exitCode: Int32 = 0, stdout: String = "", stderr: String = "") {
        self.exitCode = exitCode; self.stdout = stdout; self.stderr = stderr
    }
}

// MARK: - Output shapes (stable JSON for scripts)

public struct StatusDTO: Equatable, Codable, Sendable {
    public struct DisplayDTO: Equatable, Codable, Sendable {
        public let id: UInt32
        public let name: String
        public let main: Bool
        public let workspace: String?
    }
    public let project: String?
    public let mode: String
    public let focusedWorkspace: String
    public let displays: [DisplayDTO]
}

public struct WindowDTO: Equatable, Codable, Sendable {
    public let id: UInt32
    public let app: String
    public let bundleId: String?
    public let pid: Int32
    public let title: String
    public let project: String?
    public let workspace: String
    public let visible: Bool
    public let floating: Bool
    public let frozen: Bool
}

public struct WorkspaceDTO: Equatable, Codable, Sendable {
    public let name: String
    public let display: String
    public let shown: Bool
    public let focused: Bool
    public let layout: String
    /// Windows on screen when the workspace is shown under the active project.
    public let windows: Int
}

public struct ProjectDTO: Equatable, Codable, Sendable {
    public let name: String
    public let active: Bool
    public let windows: Int
}

// MARK: - Handling

/// Answers CLI requests from the engine. `subscribe` is handled by the transport.
@MainActor
public struct CLIHandler {
    let engine: Engine

    public init(engine: Engine) { self.engine = engine }

    /// `client`: the client process and its ancestors, the opener for `open`.
    public func handle(_ request: CLIRequest, client: [Int32] = []) -> CLIResponse {
        switch request {
        case .help:
            return CLIResponse(stdout: CLIRequest.usage + "\n")
        case .run(let script, let window):
            let errors = engine.run(script, window: window)
            return errors.isEmpty
                ? CLIResponse() : CLIResponse(exitCode: 1, stderr: errors.joined(separator: "\n") + "\n")
        case .open(let url):
            let errors = engine.openURL(url, opener: client)
            return errors.isEmpty
                ? CLIResponse() : CLIResponse(exitCode: 1, stderr: errors.joined(separator: "\n") + "\n")
        case .status(let json):
            engine.refresh()
            let s = status()
            if json { return Self.json(s) }
            let shown = s.displays.map { d in
                let ws = d.workspace ?? "-"
                return "\(d.name): \(ws == s.focusedWorkspace ? "[\(ws)]" : ws)"
            }
            return CLIResponse(
                stdout: "project: \(s.project ?? "-")\nmode: \(s.mode)\n" + shown.joined(separator: "\n") + "\n")
        case .listWindows(let filter, let json):
            engine.refresh()
            let windows = windows(filter)
            if json { return Self.json(windows) }
            return Self.table(
                ["ID", "APP", "PROJECT", "WS", "STATE", "TITLE"],
                windows.map { w in
                    let state = [w.visible ? "shown" : "hidden", w.floating ? "float" : nil, w.frozen ? "frozen" : nil]
                    return [
                        String(w.id), w.app, w.project ?? "-", w.workspace,
                        state.compactMap { $0 }.joined(separator: ","), w.title,
                    ]
                })
        case .listWorkspaces(let json):
            engine.refresh()
            let list = workspaces()
            if json { return Self.json(list) }
            return Self.table(
                ["NAME", "DISPLAY", "STATE", "LAYOUT", "WINDOWS"],
                list.map { w in
                    [w.name, w.display, w.focused ? "focused" : w.shown ? "shown" : "-", w.layout, String(w.windows)]
                })
        case .listProjects(let json):
            engine.refresh()
            let list = projects()
            if json { return Self.json(list) }
            return Self.table(
                ["NAME", "ACTIVE", "WINDOWS"], list.map { [$0.name, $0.active ? "*" : "", String($0.windows)] })
        case .subscribe:
            return CLIResponse(exitCode: 2, stderr: "subscribe needs a streaming connection\n")
        }
    }

    public func status() -> StatusDTO {
        StatusDTO(
            project: engine.activeProject, mode: engine.mode, focusedWorkspace: engine.focusedWorkspace,
            displays: engine.displays.sorted { ($0.isMain ? 0 : 1, $0.frame.x) < ($1.isMain ? 0 : 1, $1.frame.x) }
                .map {
                    StatusDTO.DisplayDTO(
                        id: $0.id.raw, name: $0.name, main: $0.isMain, workspace: engine.state.activeWorkspace[$0.id])
                })
    }

    func windows(_ f: CLIRequest.WindowFilter) -> [WindowDTO] {
        engine.windowList()
            .filter { w in
                switch f.owner {
                case .any: true
                case .project(let p): w.record.owner == p
                case .unlinked: w.record.owner == nil
                case .active: w.record.owner != nil && w.record.owner == engine.activeProject
                }
            }
            .filter { f.workspace == nil || $0.record.workspace == f.workspace }
            .filter { !f.visibleOnly || $0.visible }
            .filter { f.pid == nil || $0.facts.pid == f.pid }
            .map { w in
                WindowDTO(
                    id: w.id.raw, app: w.facts.appName, bundleId: w.facts.bundleID, pid: w.facts.pid,
                    title: w.facts.title, project: w.record.owner, workspace: w.record.workspace, visible: w.visible,
                    floating: w.record.floating, frozen: w.facts.isFrozen)
            }
    }

    public func workspaces() -> [WorkspaceDTO] {
        let shown = Set(engine.state.activeWorkspace.values)
        let windows = engine.windowList()
        return engine.displays.sorted { ($0.isMain ? 0 : 1, $0.frame.x) < ($1.isMain ? 0 : 1, $1.frame.x) }
            .flatMap { d in
                engine.workspaces(on: d).map { ws in
                    WorkspaceDTO(
                        name: ws, display: d.name, shown: shown.contains(ws), focused: ws == engine.focusedWorkspace,
                        layout: engine.layout(of: ws).kind.rawValue,
                        windows: windows.filter {
                            $0.record.workspace == ws && !$0.facts.isFrozen
                                && ($0.record.owner == nil || $0.record.owner == engine.activeProject)
                        }.count)
                }
            }
    }

    func projects() -> [ProjectDTO] {
        let windows = engine.windowList()
        return engine.config.projects.map { p in
            ProjectDTO(
                name: p.name, active: p.name == engine.activeProject,
                windows: windows.filter { $0.record.owner == p.name }.count)
        }
    }

    // MARK: - Formatting

    static func json<T: Encodable>(_ value: T) -> CLIResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return CLIResponse(exitCode: 1, stderr: "encoding failed\n") }
        return CLIResponse(stdout: String(decoding: data, as: UTF8.self) + "\n")
    }

    /// Space-aligned columns; the last column is not padded.
    static func table(_ header: [String], _ rows: [[String]]) -> CLIResponse {
        let all = [header] + rows
        let widths = header.indices.map { i in all.map { $0[i].count }.max() ?? 0 }
        let lines = all.map { row in
            row.enumerated().map { i, cell in
                i == row.count - 1 ? cell : cell.padding(toLength: widths[i], withPad: " ", startingAt: 0)
            }
            .joined(separator: "  ")
        }
        return CLIResponse(stdout: lines.joined(separator: "\n") + "\n")
    }
}

import Foundation

/// The window manager: keeps `State` in sync with the OS and executes commands.
///
/// Visibility rule: a window is on screen iff its workspace is the active one on its display and it is
/// either unlinked or linked to the active project. Everything else is parked off-screen.
@MainActor
public final class Engine {
    public private(set) var config: Config
    public private(set) var state: State
    public private(set) var mode = "main"
    public private(set) var displays: [Display] = []
    public private(set) var facts: [WindowID: WindowFacts] = [:]

    /// Called when the mode changes or the config reloads: hotkeys must be re-registered.
    public var onBindingsChange: (() -> Void)?
    /// Called after every state change, e.g. to update the menu bar.
    public var onChange: (() -> Void)?
    /// Diagnostics: project/workspace switches and launches, with the reason.
    public var onLog: ((String) -> Void)?

    private let windowSystem: WindowSystem
    private let launcher: Launcher
    private let store: StateStore
    private let configSource: ConfigSource
    private let clock: Clock

    struct PendingLaunch {
        let project: String
        let app: String
        let at: Date
    }
    private var pendingLaunches: [PendingLaunch] = []
    /// New windows of an app launched for a project within this interval are linked to that project.
    static let launchLinkInterval: TimeInterval = 30
    /// Explicit target of the running command, see `run(_:window:)`.
    private var target: WindowID?
    /// Last focused window reported by the OS; a change means the user focused something.
    private var lastSeenFocus: WindowID?
    /// The focus found at startup is not a user action: it may be a stale focus on a parked window.
    private var hasSeenFocus = false

    public init(
        config: Config, windowSystem: WindowSystem, launcher: Launcher, store: StateStore,
        configSource: ConfigSource, clock: Clock = SystemClock()
    ) {
        self.config = config
        self.windowSystem = windowSystem
        self.launcher = launcher
        self.store = store
        self.configSource = configSource
        self.clock = clock
        self.state = store.load() ?? State()
    }

    // MARK: - Queries

    public var activeProject: String? { state.activeProject }
    public var focusedWorkspace: String { state.focusedWorkspace ?? "" }

    public func display(of workspace: String) -> Display {
        if let id = state.workspaceDisplay[workspace], let d = displays.first(where: { $0.id == id }) { return d }
        if let d = config.workspaces[workspace]?.resolve(in: displays) { return d }
        return mainDisplay
    }

    public func isVisible(_ r: WindowRecord) -> Bool {
        state.activeWorkspace[display(of: r.workspace).id] == r.workspace
            && (r.owner == nil || r.owner == state.activeProject)
    }

    /// The workspace's layout under the active project.
    public func layout(of workspace: String) -> Layout {
        state.layouts[State.focusKey(project: state.activeProject, workspace: workspace)]
            ?? config.workspaceLayouts[workspace] ?? config.defaultLayout
    }

    /// Visible windows of a workspace, in workspace order.
    public func visibleWindows(in workspace: String) -> [WindowID] {
        state.windows
            .filter { $0.value.workspace == workspace && isVisible($0.value) && facts[$0.key]?.isFrozen == false }
            .sorted { $0.value.seq < $1.value.seq }
            .map(\.key)
    }

    private var mainDisplay: Display { displays.first(where: \.isMain) ?? displays[0] }

    private var allWorkspaces: [String] {
        Set(config.workspaces.keys)
            .union(state.workspaceDisplay.keys)
            .union(state.windows.values.map(\.workspace))
            .union(state.activeWorkspace.values)
            .sorted()
    }

    public func workspaces(on d: Display) -> [String] { allWorkspaces.filter { display(of: $0).id == d.id } }

    public struct WindowInfo: Equatable, Sendable {
        public let facts: WindowFacts
        public let record: WindowRecord
        /// On screen now: its workspace is shown, its project is active (or it is unlinked), not frozen.
        public let visible: Bool
        public var id: WindowID { facts.id }
    }

    /// Managed windows by workspace, then workspace order.
    public func windowList() -> [WindowInfo] {
        state.windows.compactMap { id, r in
            facts[id].map { WindowInfo(facts: $0, record: r, visible: isVisible(r) && !$0.isFrozen) }
        }
        .sorted { ($0.record.workspace, $0.record.seq) < ($1.record.workspace, $1.record.seq) }
    }

    private func neighbour(of d: Display, _ dir: Direction) -> Display {
        let sorted = displays.sorted { $0.frame.x < $1.frame.x }
        let i = sorted.firstIndex { $0.id == d.id } ?? 0
        return sorted[(i + (dir == .next ? 1 : -1) + sorted.count) % sorted.count]
    }

    // MARK: - Sync

    /// Re-reads the OS state, links new windows, follows user focus changes and applies the layout.
    public func refresh() {
        let before = state
        guard sync() else { return }
        apply()
        finish(before)
    }

    /// Returns false when there are no displays (e.g. during sleep): nothing can be laid out.
    private func sync() -> Bool {
        displays = windowSystem.displays()
        guard !displays.isEmpty else { return false }
        let now = clock.now()
        pendingLaunches.removeAll { now.timeIntervalSince($0.at) > Self.launchLinkInterval }

        let list = windowSystem.windows().sorted { $0.id < $1.id }
        facts = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        state.windows = state.windows.filter { facts[$0.key] != nil }
        dropUnknownProjects()
        normalizeWorkspaces()

        let linker = Linker(config: config)
        let planner = Planner(displays: displays, gap: config.gap)
        for w in list {
            if var r = state.windows[w.id] {
                if r.owner == nil && !r.manual, let p = linker.match(w).project {
                    r.owner = p  // e.g. the window got renamed to match a title rule
                }
                if r.floating && !w.isFrozen && isVisible(r) && planner.isOnScreen(w.frame) {
                    r.floatingFrame = w.frame
                }
                state.windows[w.id] = r
            } else {
                let m = linker.match(w)
                if m.app?.manage == false { continue }
                state.windows[w.id] = newRecord(m, linker: linker, now: now)
            }
        }
        followUserFocus()
        return true
    }

    private func newRecord(_ m: Linker.Match, linker: Linker, now: Date) -> WindowRecord {
        var owner = m.project
        if owner == nil, let app = m.app {
            owner = pendingLaunches.last { $0.app == app.id }?.project
            if owner == nil, app.newWindows == .activeProject, let active = state.activeProject,
                config.project(active)?.ref(app.id) != nil
            {
                owner = active
            }
        }
        let workspace = linker.workspace(app: m.app?.id, project: owner) ?? focusedWorkspace
        ensureKnown(workspace)
        defer { state.nextSeq += 1 }
        return WindowRecord(
            owner: owner, workspace: workspace, app: m.app?.id, floating: m.app?.floating ?? false,
            seq: state.nextSeq)
    }

    private func dropUnknownProjects() {
        let names = Set(config.projects.map(\.name))
        if let a = state.activeProject, !names.contains(a) { state.activeProject = nil }
        for (id, r) in state.windows where r.owner.map({ !names.contains($0) }) == true {
            state.windows[id]?.owner = nil
        }
    }

    /// Every display shows exactly one workspace; the focused workspace is one of them.
    private func normalizeWorkspaces() {
        for (d, ws) in state.activeWorkspace
        where !displays.contains(where: { $0.id == d }) || display(of: ws).id != d {
            state.activeWorkspace[d] = nil
        }
        for (i, d) in displays.enumerated() where state.activeWorkspace[d.id] == nil {
            if let ws = workspaces(on: d).first {
                state.activeWorkspace[d.id] = ws
            } else {
                let name = "display-\(i + 1)"
                state.workspaceDisplay[name] = d.id
                state.activeWorkspace[d.id] = name
            }
        }
        if state.focusedWorkspace.map({ !state.activeWorkspace.values.contains($0) }) ?? true {
            state.focusedWorkspace = state.activeWorkspace[mainDisplay.id]
        }
    }

    /// Workspaces not in the config live on the display they were first used on.
    private func ensureKnown(_ workspace: String) {
        if config.workspaces[workspace] == nil && state.workspaceDisplay[workspace] == nil {
            state.workspaceDisplay[workspace] = display(of: focusedWorkspace).id
        }
    }

    /// The user focused a window (Cmd-Tab, Dock, click, notification). If it is hidden, bring its project
    /// and workspace forward.
    private func followUserFocus() {
        let f = windowSystem.focusedWindow()
        guard f != lastSeenFocus || !hasSeenFocus else { return }
        lastSeenFocus = f
        guard hasSeenFocus else {
            // At launch Foci itself is frontmost (no focused window); the first real focus is not a user action.
            hasSeenFocus = f != nil
            return
        }
        guard let f, let r = state.windows[f] else { return }
        if !isVisible(r) {
            onLog?("focus moved to hidden window \(f) (\(r.app ?? "?"), project \(r.owner ?? "-"), workspace \(r.workspace)): following")
            if let owner = r.owner, owner != state.activeProject { setProject(owner) }
            showWorkspace(r.workspace)
        }
        state.focusedWorkspace = r.workspace
        rememberFocus(f)
    }

    // MARK: - Commands

    /// Runs a command script such as `workspace w; mode main`. Returns error messages.
    /// Window commands act on `window` if given (e.g. picked in the menu), else on the focused window.
    @discardableResult
    public func run(_ script: String, window: WindowID? = nil) -> [String] {
        do {
            return run(try Command.parseScript(script), window: window)
        } catch {
            return ["\(error)"]
        }
    }

    @discardableResult
    public func run(_ commands: [Command], window: WindowID? = nil) -> [String] {
        let before = state
        guard sync() else { return ["no displays"] }
        target = window
        defer { target = nil }
        var errors: [String] = []
        for c in commands {
            if let e = execute(c) { errors.append(e) }
        }
        apply()
        lastSeenFocus = windowSystem.focusedWindow()
        hasSeenFocus = true
        finish(before)
        return errors
    }

    private func execute(_ command: Command) -> String? {
        switch command {
        case .project(let target):
            let names = config.projects.map(\.name)
            let p: String?
            switch target {
            case .named(let n):
                guard names.contains(n) else { return "unknown project '\(n)'" }
                p = n
            case .none: p = nil
            case .cycle(let dir):
                guard !names.isEmpty else { return "no projects configured" }
                if let a = state.activeProject, let i = names.firstIndex(of: a) {
                    p = names[(i + (dir == .next ? 1 : -1) + names.count) % names.count]
                } else {
                    p = dir == .next ? names.first : names.last
                }
            case .backAndForth:
                guard let prev = state.previousProject else { return nil }
                p = prev.name
            }
            setProject(p)
            apply()
            focusBest(in: focusedWorkspace)
            autostart(in: Set(state.activeWorkspace.values))

        case .workspace(let target):
            let ws: String
            switch target {
            case .named(let n): ws = n
            case .cycle(let dir):
                let list = workspaces(on: display(of: focusedWorkspace))
                let i = list.firstIndex(of: focusedWorkspace) ?? 0
                ws = list[(i + (dir == .next ? 1 : -1) + list.count) % list.count]
            case .backAndForth:
                guard let prev = state.previousWorkspace else { return nil }
                ws = prev
            }
            showWorkspace(ws)
            apply()
            focusBest(in: ws)
            autostart(in: [ws])

        case .moveToWorkspace(let ws, let follow):
            guard let id = focusedManagedWindow() else { return "no focused window" }
            ensureKnown(ws)
            state.windows[id]?.workspace = ws
            if follow { showWorkspace(ws) }
            apply()
            if follow { focus(id) } else { focusBest(in: focusedWorkspace) }

        case .moveWorkspaceToDisplay(let dir):
            let ws = focusedWorkspace
            let from = display(of: ws)
            let to = neighbour(of: from, dir)
            guard to.id != from.id else { return nil }
            state.workspaceDisplay[ws] = to.id
            state.activeWorkspace[from.id] = nil
            state.activeWorkspace[to.id] = ws
            normalizeWorkspaces()
            apply()
            focusBest(in: ws)

        case .focusDisplay(let dir):
            let to = neighbour(of: display(of: focusedWorkspace), dir)
            guard let ws = state.activeWorkspace[to.id] else { return nil }
            state.focusedWorkspace = ws
            focusBest(in: ws)

        case .focusWindow(let dir):
            let list = visibleWindows(in: focusedWorkspace)
            guard !list.isEmpty else { return nil }
            let i = windowSystem.focusedWindow().flatMap { list.firstIndex(of: $0) }
            let next = i.map { (($0 + (dir == .next ? 1 : -1)) + list.count) % list.count } ?? 0
            focus(list[next])

        case .moveWindow(let dir):
            guard let id = focusedManagedWindow(), state.windows[id]?.floating == false else {
                return "no focused tiled window"
            }
            let list = tiledWindows(in: focusedWorkspace)
            guard list.count > 1, let i = list.firstIndex(of: id) else { return nil }
            let other = list[(i + (dir == .next ? 1 : -1) + list.count) % list.count]
            let seq = state.windows[id]!.seq
            state.windows[id]!.seq = state.windows[other]!.seq
            state.windows[other]!.seq = seq
            apply()
            focus(id)

        case .layout(let change):
            let ws = focusedWorkspace
            var l = layout(of: ws)
            switch change {
            case .set(let kind): l.kind = kind
            case .toggle: l.kind = l.kind == .tiles ? .maximized : .tiles
            case .toggleOrientation:
                let area = display(of: ws).visibleFrame
                let horizontal = Planner(displays: displays, gap: config.gap).isHorizontal(l, area)
                l.kind = .tiles
                l.orientation = horizontal ? .vertical : .horizontal
            }
            state.layouts[State.focusKey(project: state.activeProject, workspace: ws)] = l
            apply()
            focusBest(in: ws)

        case .resize(let points):
            guard let id = focusedManagedWindow() else { return "no focused window" }
            let ws = focusedWorkspace
            let list = tiledWindows(in: ws)
            guard layout(of: ws).kind == .tiles, list.count > 1, list.contains(id) else { return nil }
            let planner = Planner(displays: displays, gap: config.gap)
            let area = display(of: ws).visibleFrame.insetBy(config.gap)
            let length = planner.tileLength(
                count: list.count, area: area, horizontal: planner.isHorizontal(layout(of: ws), area))
            let total = list.reduce(0) { $0 + state.windows[$1]!.weight }
            let w = state.windows[id]!.weight
            // Choose the new weight so that the tile grows by exactly `points` (others shrink proportionally).
            let share = min(max(w / total + points / length, 0.05), 0.95)
            state.windows[id]!.weight = w + (share * total - w) / (1 - share)
            apply()

        case .balance:
            for id in tiledWindows(in: focusedWorkspace) { state.windows[id]?.weight = 1 }
            apply()

        case .reveal:
            guard let id = focusedManagedWindow() ?? windowSystem.focusedWindow(), let r = state.windows[id] else {
                return "no window"
            }
            if let owner = r.owner { setProject(owner) }
            showWorkspace(r.workspace)
            apply()
            focus(id)

        case .link(let name):
            guard let id = focusedManagedWindow() else { return "no focused window" }
            guard let p = name ?? state.activeProject else { return "no active project" }
            guard config.project(p) != nil else { return "unknown project '\(p)'" }
            state.windows[id]?.owner = p
            state.windows[id]?.manual = true
            apply()
            if let r = state.windows[id], !isVisible(r) { focusBest(in: focusedWorkspace) }

        case .unlink:
            guard let id = focusedManagedWindow() else { return "no focused window" }
            state.windows[id]?.owner = nil
            state.windows[id]?.manual = true

        case .toggleFloat:
            guard let id = focusedManagedWindow(), var r = state.windows[id] else { return "no focused window" }
            r.floating.toggle()
            if r.floating {
                let a = display(of: r.workspace).visibleFrame
                r.floatingFrame = Rect(
                    x: a.x + a.width * 0.15, y: a.y + a.height * 0.15, width: a.width * 0.7, height: a.height * 0.7)
            }
            state.windows[id] = r
            apply()
            focus(id)

        case .launch(let app):
            guard let def = config.apps[app] else { return "unknown app '\(app)'" }
            let project = state.activeProject.flatMap { p in config.project(p)?.ref(app) != nil ? p : nil }
            if let id = newestWindow(app: app, owner: project) {
                showWorkspace(state.windows[id]!.workspace)
                apply()
                focus(id)
            } else if let project {
                return launch(def, ref: config.project(project)!.ref(app)!, project: project)
            } else if let cmd = def.globalLaunch {
                launcher.run(cmd, environment: [:])
            } else {
                return "app '\(app)' has no global-launch command"
            }

        case .mode(let m):
            guard config.modes[m] != nil else { return "unknown mode '\(m)'" }
            mode = m
            onBindingsChange?()

        case .reloadConfig:
            do {
                config = try configSource.load()
                if config.modes[mode] == nil { mode = "main" }
                dropUnknownProjects()
                normalizeWorkspaces()
                onBindingsChange?()
                let problems = config.validate()
                return problems.isEmpty ? nil : problems.joined(separator: "\n")
            } catch {
                return "config: \(error)"
            }

        case .exec(let cmd):
            launcher.run(cmd, environment: state.activeProject.map { ["FOCI_PROJECT": $0] } ?? [:])
        }
        return nil
    }

    // MARK: - Steps

    private func setProject(_ p: String?) {
        guard p != state.activeProject else { return }
        onLog?("project \(state.activeProject ?? "-") -> \(p ?? "-")")
        state.previousProject = ProjectSlot(state.activeProject)
        state.activeProject = p
    }

    private func showWorkspace(_ ws: String) {
        ensureKnown(ws)
        if state.focusedWorkspace != ws {
            onLog?("workspace \(focusedWorkspace) -> \(ws)")
            state.previousWorkspace = state.focusedWorkspace
        }
        state.activeWorkspace[display(of: ws).id] = ws
        state.focusedWorkspace = ws
    }

    private func focusedManagedWindow() -> WindowID? {
        if let target { return state.windows[target] != nil ? target : nil }
        guard let id = windowSystem.focusedWindow(), let r = state.windows[id], isVisible(r) else { return nil }
        return id
    }

    private func focus(_ id: WindowID) {
        windowSystem.focus(id)
        rememberFocus(id)
    }

    private func rememberFocus(_ id: WindowID) {
        guard let r = state.windows[id] else { return }
        state.lastFocused[State.focusKey(project: state.activeProject, workspace: r.workspace)] = id
    }

    /// The window last focused in this workspace under the active project, else the first one.
    private func focusBest(in ws: String) {
        let candidates = visibleWindows(in: ws)
        if let id = state.lastFocused[State.focusKey(project: state.activeProject, workspace: ws)],
            candidates.contains(id)
        {
            focus(id)
        } else if let id = candidates.first {
            focus(id)
        }
    }

    /// Visible, non-floating windows of a workspace, in tile order.
    private func tiledWindows(in ws: String) -> [WindowID] {
        visibleWindows(in: ws).filter { state.windows[$0]?.floating == false }
    }

    private func newestWindow(app: String, owner: String?) -> WindowID? {
        state.windows.filter { $0.value.app == app && $0.value.owner == owner && facts[$0.key]?.isFrozen == false }
            .max { $0.value.seq < $1.value.seq }?.key
    }

    /// Launches the active project's autostart apps that belong to one of `workspaces` and have no window yet.
    private func autostart(in workspaces: Set<String>) {
        guard let p = state.activeProject, let project = config.project(p) else { return }
        let linker = Linker(config: config)
        for ref in project.apps where ref.autostart {
            guard let ws = linker.workspace(app: ref.app, project: p), workspaces.contains(ws),
                let def = config.apps[ref.app],
                !state.windows.values.contains(where: { $0.owner == p && $0.app == ref.app })
            else { continue }
            _ = launch(def, ref: ref, project: p)
        }
    }

    private func launch(_ def: AppDef, ref: ProjectAppRef, project: String) -> String? {
        guard let template = def.launch else { return "app '\(def.id)' has no launch command" }
        if pendingLaunches.contains(where: { $0.app == def.id && $0.project == project }) { return nil }
        let command = template
            .replacingOccurrences(of: "{project}", with: project)
            .replacingOccurrences(of: "{open}", with: ref.open.map(Self.shellQuote).joined(separator: " "))
        onLog?("launch \(def.id) for \(project): \(command)")
        launcher.run(command, environment: ["FOCI_PROJECT": project])
        pendingLaunches.append(PendingLaunch(project: project, app: def.id, at: clock.now()))
        return nil
    }

    static func shellQuote(_ s: String) -> String {
        if s.hasPrefix("~/") {
            let rest = s.dropFirst(2).replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "$", with: "\\$").replacingOccurrences(of: "`", with: "\\`")
            return "\"$HOME/\(rest)\""
        }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Moves every window to its planned frame. Shown windows first to reduce flicker.
    private func apply() {
        let planner = Planner(displays: displays, gap: config.gap)
        let targets = planner.plan(
            records: state.windows, facts: facts, isVisible: isVisible, displayOf: display(of:),
            layoutOf: layout(of:))
        for t in targets {
            guard let f = facts[t.id], !f.frame.isClose(to: t.frame) else { continue }
            windowSystem.setFrame(t.id, t.frame)
            facts[t.id]?.frame = t.frame
        }
    }

    private func finish(_ before: State) {
        if state != before { store.save(state) }
        onChange?()
    }

    /// Puts every managed window back on screen. Called on quit so nothing stays parked.
    public func restoreAll() {
        guard !displays.isEmpty else { return }
        let planner = Planner(displays: displays, gap: config.gap)
        let targets = planner.plan(
            records: state.windows, facts: facts, isVisible: { _ in true }, displayOf: display(of:),
            layoutOf: layout(of:))
        for t in targets {
            guard let f = facts[t.id], !f.frame.isClose(to: t.frame) else { continue }
            windowSystem.setFrame(t.id, t.frame)
        }
    }
}

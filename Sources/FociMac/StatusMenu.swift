import AppKit
import FociCore

/// Menu bar item `WORK · w`. The menu is built when opened: projects, workspaces per display, layout,
/// and every managed window with its own actions.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    /// Runs a command script, optionally targeting a specific window instead of the focused one.
    var onCommand: ((String, WindowID?) -> Void)?
    var onEditConfig: (() -> Void)?
    /// Foci waits for the Accessibility permission: the menu says how to grant it.
    var needsAccessibility = false
    var onOpenAccessibilitySettings: (() -> Void)?
    var onResetAccessibility: (() -> Void)?
    weak var engine: Engine?

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var problems: [String] = []
    private var labelContent: MenuBarLabel.Content?

    override init() {
        super.init()
        // macOS remembers where the item was ⌘-dragged. When the menu bar is full (a laptop display alone),
        // it hides status items from the left, and new items start leftmost.
        item.autosaveName = "dev.foci.status"
        item.button?.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        item.button?.title = "Foci"
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
    }

    func setProblems(_ p: [String]) { problems = p }

    func setTitle(_ title: String) { item.button?.title = title }

    func update() {
        guard let engine, let button = item.button else { return }
        let style = engine.config.menuBarStyle
        if style != .text {
            let content = MenuBarLabel.content(engine, style: style, warning: !problems.isEmpty)
            // Rendering is cheap but updates come with every refresh.
            if content == labelContent, button.image != nil { return }
            if let image = MenuBarLabel.image(content) {
                labelContent = content
                button.image = image
                button.title = ""
                button.setAccessibilityLabel(textTitle(engine).string)
                return
            }
        }
        labelContent = nil
        button.image = nil
        button.attributedTitle = textTitle(engine)
    }

    /// `WORK · [w] x`: the workspace shown on each display (left to right), the focused one bold in brackets.
    /// The focused window's project follows the active one, dimmed, when they differ: `WORK ⊘ · …` if unlinked.
    private func textTitle(_ engine: Engine) -> NSAttributedString {
        let size = NSFont.systemFontSize
        let regular: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: size, weight: .medium)]
        let focused: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: size, weight: .bold)]
        let dimmed: [NSAttributedString.Key: Any] = regular.merging([.foregroundColor: NSColor.secondaryLabelColor]) {
            $1
        }

        let title = NSMutableAttributedString(string: engine.activeProject?.uppercased() ?? "–", attributes: regular)
        if let outside = engine.focusedOutsider {
            title.append(NSAttributedString(string: " " + (outside.owner?.uppercased() ?? "⊘"), attributes: dimmed))
        }
        title.append(NSAttributedString(string: " ·", attributes: regular))
        for d in sortedDisplays(engine) {
            guard let ws = engine.state.activeWorkspace[d.id] else { continue }
            let isFocused = ws == engine.focusedWorkspace
            title.append(NSAttributedString(string: " ", attributes: regular))
            title.append(NSAttributedString(string: isFocused ? "[\(ws)]" : ws, attributes: isFocused ? focused : dimmed))
        }
        if engine.mode != "main" { title.append(NSAttributedString(string: " (\(engine.mode))", attributes: dimmed)) }
        if !problems.isEmpty { title.append(NSAttributedString(string: " ⚠", attributes: regular)) }
        return title
    }

    /// Left to right, as numbered in 'focus-display 1'.
    private func sortedDisplays(_ engine: Engine) -> [Display] { engine.orderedDisplays }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if needsAccessibility { buildAccessibilityHelp(menu) }
        if let engine { build(menu, engine) }
        for p in problems.prefix(10) { menu.addItem(disabled("⚠ " + p)) }
        if !problems.isEmpty { menu.addItem(.separator()) }
        menu.addItem(command("Reload Config", "reload-config"))
        menu.addItem(action("Edit Config", #selector(editConfig)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Foci", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func buildAccessibilityHelp(_ menu: NSMenu) {
        menu.addItem(header("Accessibility Permission Needed"))
        menu.addItem(disabled("Foci moves windows through Accessibility. Turn on Foci in"))
        menu.addItem(disabled("System Settings → Privacy & Security → Accessibility; Foci starts by itself."))
        menu.addItem(action("Open Accessibility Settings…", #selector(openAccessibilitySettings)))
        menu.addItem(disabled("Foci is on there but still asks (after an update)? Reset it:"))
        menu.addItem(action("Reset Permission and Ask Again", #selector(resetAccessibility)))
        menu.addItem(.separator())
    }

    @objc private func openAccessibilitySettings() { onOpenAccessibilitySettings?() }
    @objc private func resetAccessibility() { onResetAccessibility?() }

    private func build(_ menu: NSMenu, _ engine: Engine) {
        let projects = engine.config.projects.map(\.name)

        menu.addItem(header("Project"))
        for p in projects { menu.addItem(command(p.uppercased(), "project \(p)", checked: engine.activeProject == p)) }
        menu.addItem(command("No Project", "project --none", checked: engine.activeProject == nil))
        menu.addItem(.separator())

        // The focused window, as the label marks it when it is outside the project.
        let windows = engine.windowList()
        if let id = engine.focusedRecord?.id, let w = windows.first(where: { $0.id == id }) {
            menu.addItem(header("Window"))
            menu.addItem(windowItem(w, engine: engine, projects: projects, markUnlinked: true))
            menu.addItem(.separator())
        }

        // One row per display, the workspaces in a submenu: every letter can be a workspace, too many rows for a
        // laptop screen.
        let displays = sortedDisplays(engine)
        menu.addItem(header("Workspaces"))
        for (n, d) in displays.enumerated() {
            let active = engine.state.activeWorkspace[d.id]
            let sub = NSMenu()
            sub.autoenablesItems = false
            for ws in engine.workspaces(on: d) {
                let i = command(ws, "workspace \(ws)", checked: ws == active)
                if ws == engine.focusedWorkspace { i.title += "  ◂" }
                sub.addItem(i)
            }
            if displays.count > 1, active == engine.focusedWorkspace {
                sub.addItem(.separator())
                for (m, other) in displays.enumerated() where other.id != d.id {
                    sub.addItem(command(
                        "Move \"\(engine.focusedWorkspace)\" to \(m + 1)  \(engine.label(of: other))", "move-workspace-to-display \(m + 1)"))
                }
            }
            // Numbered as in 'focus-display 1': two monitors of one model have the same name.
            let number = displays.count > 1 ? "\(n + 1)  " : ""
            let item = NSMenuItem(title: "\(number)\(engine.label(of: d)): \(active ?? "–")", action: nil, keyEquivalent: "")
            item.toolTip = d.name
            if active == engine.focusedWorkspace, displays.count > 1 { item.title += "  ◂" }
            item.submenu = sub
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let layout = engine.layout(of: engine.focusedWorkspace)
        let layoutMenu = NSMenu()
        layoutMenu.autoenablesItems = false
        layoutMenu.addItem(command("Maximized", "layout maximized", checked: layout.kind == .maximized))
        layoutMenu.addItem(command("Tiles", "layout tiles", checked: layout.kind == .tiles))
        layoutMenu.addItem(command("Rotate Tiles", "layout toggle-orientation"))
        layoutMenu.addItem(command("Balance Tiles", "balance", enabled: layout.kind == .tiles))
        let layoutItem = NSMenuItem(
            title: "Layout · \(engine.focusedWorkspace): \(layout.kind == .tiles ? "Tiles" : "Maximized")",
            action: nil, keyEquivalent: "")
        layoutItem.submenu = layoutMenu
        menu.addItem(layoutItem)
        menu.addItem(.separator())

        let windowsItem = NSMenuItem(title: "Windows (\(windows.count))", action: nil, keyEquivalent: "")
        let windowsMenu = NSMenu()
        windowsMenu.autoenablesItems = false
        var lastWorkspace: String?
        for w in windows {
            if w.record.workspace != lastWorkspace {
                if lastWorkspace != nil { windowsMenu.addItem(.separator()) }
                windowsMenu.addItem(header("Workspace \(w.record.workspace)"))
                lastWorkspace = w.record.workspace
            }
            windowsMenu.addItem(windowItem(w, engine: engine, projects: projects))
        }
        windowsItem.submenu = windowsMenu
        menu.addItem(windowsItem)
        menu.addItem(.separator())
    }

    /// "Chrome — Inbox   [work]" with a submenu of actions on that window; `markUnlinked`: "[⊘]" if unlinked.
    private func windowItem(
        _ w: Engine.WindowInfo, engine: Engine, projects: [String], markUnlinked: Bool = false
    ) -> NSMenuItem {
        var title = w.facts.title.isEmpty ? w.facts.appName : "\(w.facts.appName) — \(w.facts.title)"
        if title.count > 60 { title = String(title.prefix(59)) + "…" }
        let owner = w.record.owner?.uppercased() ?? (markUnlinked ? "⊘" : nil)
        let tag = [owner, w.record.floating ? "float" : nil].compactMap { $0 }.joined(separator: ", ")
        if !tag.isEmpty { title += "   [\(tag)]" }

        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.state = w.visible ? .on : .off
        let sub = NSMenu()
        sub.autoenablesItems = false
        sub.addItem(command("Show", "reveal", window: w.id))
        sub.addItem(.separator())
        sub.addItem(header("Link to Project"))
        for p in projects {
            sub.addItem(command(p.uppercased(), "link \(p)", window: w.id, checked: w.record.owner == p))
        }
        sub.addItem(command("Unlinked", "unlink", window: w.id, checked: w.record.owner == nil))
        sub.addItem(.separator())

        let move = NSMenuItem(title: "Move to Workspace", action: nil, keyEquivalent: "")
        let moveMenu = NSMenu()
        moveMenu.autoenablesItems = false
        for d in engine.displays {
            for ws in engine.workspaces(on: d) {
                moveMenu.addItem(
                    command(ws, "move-to-workspace \(ws)", window: w.id, checked: w.record.workspace == ws))
            }
        }
        move.submenu = moveMenu
        sub.addItem(move)
        sub.addItem(command("Float", "float", window: w.id, checked: w.record.floating, enabled: w.visible))
        item.submenu = sub
        return item
    }

    // MARK: - Items

    private struct Action {
        let script: String
        let window: WindowID?
    }

    private func command(
        _ title: String, _ script: String, window: WindowID? = nil, checked: Bool = false, enabled: Bool = true
    ) -> NSMenuItem {
        let i = action(title, #selector(runCommand(_:)))
        i.representedObject = Action(script: script, window: window)
        i.state = checked ? .on : .off
        i.isEnabled = enabled
        return i
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        i.target = self
        return i
    }

    private func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return NSMenuItem.sectionHeader(title: title) }
        return disabled(title)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let a = sender.representedObject as? Action else { return }
        onCommand?(a.script, a.window)
    }

    @objc private func editConfig() { onEditConfig?() }
}

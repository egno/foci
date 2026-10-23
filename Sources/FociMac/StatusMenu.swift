import AppKit
import FociCore

/// Menu bar item: `BIL · w`. The menu switches projects and shows config problems.
@MainActor
final class StatusMenu: NSObject {
    var onCommand: ((String) -> Void)?
    var onEditConfig: (() -> Void)?

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var problems: [String] = []

    override init() {
        super.init()
        item.button?.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        show(title: "Foci", menu: nil)
    }

    func setProblems(_ p: [String]) { problems = p }

    func show(title: String, menu: NSMenu?) {
        item.button?.title = title
        item.menu = menu ?? baseMenu()
    }

    func update(engine: Engine) {
        let project = engine.activeProject?.uppercased() ?? "–"
        let mode = engine.mode == "main" ? "" : " [\(engine.mode)]"
        let warning = problems.isEmpty ? "" : " ⚠"
        item.button?.title = "\(project) · \(engine.focusedWorkspace)\(mode)\(warning)"

        let menu = NSMenu()
        for p in engine.config.projects {
            let i = menuItem(p.name, command: "project \(p.name)")
            i.state = engine.activeProject == p.name ? .on : .off
            menu.addItem(i)
        }
        let none = menuItem("No project", command: "project --none")
        none.state = engine.activeProject == nil ? .on : .off
        menu.addItem(none)
        menu.addItem(.separator())
        for p in problems.prefix(10) {
            let i = NSMenuItem(title: "⚠ " + p, action: nil, keyEquivalent: "")
            i.isEnabled = false
            menu.addItem(i)
        }
        if !problems.isEmpty { menu.addItem(.separator()) }
        let base = baseMenu()
        for i in base.items {
            base.removeItem(i)
            menu.addItem(i)
        }
        item.menu = menu
    }

    private func baseMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem("Reload Config", command: "reload-config"))
        let edit = NSMenuItem(title: "Edit Config", action: #selector(editConfig), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Foci", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func menuItem(_ title: String, command: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: #selector(runCommand(_:)), keyEquivalent: "")
        i.target = self
        i.representedObject = command
        return i
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        if let c = sender.representedObject as? String { onCommand?(c) }
    }

    @objc private func editConfig() { onEditConfig?() }
}

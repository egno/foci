import FociCore
import Foundation
import TOMLKit

public struct ConfigError: Error, CustomStringConvertible {
    public let description: String
    init(_ d: String) { description = d }
}

/// Reads `~/.config/foci/config.toml`. Unknown keys are errors, so typos don't silently do nothing.
@MainActor
public final class TOMLConfigSource: ConfigSource {
    public let url: URL

    public init(url: URL = TOMLConfigSource.defaultURL) { self.url = url }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/foci/config.toml")
    }

    public var modificationDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Writes the bundled example config if there is none yet.
    public func installDefaultIfMissing() {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? DefaultConfig.text.write(to: url, atomically: true, encoding: .utf8)
    }

    public func load() throws -> Config {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try Self.parse(text)
    }

    public static func parse(_ text: String) throws -> Config {
        let root: TOMLTable
        do {
            root = try TOMLTable(string: text)
        } catch let e as TOMLParseError {
            throw ConfigError("line \(e.source.begin.line): \(e.description)")
        }
        var c = Config()
        try checkKeys(
            root,
            ["start-at-login", "gap", "default-layout", "workspaces", "apps", "browser", "projects", "mode",
             "key-hints", "key-hints-delay", "menu-bar-style"],
            at: "top level")
        if let v = root["start-at-login"] { c.startAtLogin = try bool(v, "start-at-login") }
        if let v = root["menu-bar-style"] {
            guard let s = MenuBarStyle(rawValue: try string(v, "menu-bar-style")) else {
                throw ConfigError("menu-bar-style: expected 'text', 'squares' or 'i3'")
            }
            c.menuBarStyle = s
        }
        if let v = root["key-hints"] { c.keyHints = try bool(v, "key-hints") }
        if let v = root["key-hints-delay"] {
            let ms = try number(v, "key-hints-delay")
            guard ms >= 0 else { throw ConfigError("key-hints-delay: expected milliseconds >= 0") }
            c.keyHintsDelay = ms / 1000
        }

        if let b = root["browser"] { c.browser = try string(b, "browser") }
        if let gap = root["gap"] { c.gap = try number(gap, "gap") }
        if let l = root["default-layout"] { c.defaultLayout.kind = try layoutKind(l, "default-layout") }

        if let ws = root["workspaces"] {
            let t = try table(ws, "workspaces")
            for name in t.keys {
                let v = t[name]!
                if let s = v.string {
                    c.workspaces[name] = DisplaySpec(parsing: s)
                } else {
                    let wt = try table(v, "workspaces.\(name)")
                    let at = "workspaces.\(name)"
                    try checkKeys(wt, ["display", "layout", "orientation"], at: at)
                    c.workspaces[name] = DisplaySpec(parsing: try wt["display"].map { try string($0, "display") } ?? "main")
                    if wt["layout"] != nil || wt["orientation"] != nil {
                        var layout = c.defaultLayout
                        if let l = wt["layout"] { layout.kind = try layoutKind(l, "\(at).layout") }
                        if let o = wt["orientation"] {
                            guard let v = Orientation(rawValue: try string(o, "\(at).orientation")) else {
                                throw ConfigError("\(at).orientation: expected auto, horizontal or vertical")
                            }
                            layout.orientation = v
                        }
                        c.workspaceLayouts[name] = layout
                    }
                }
            }
        }

        if let apps = root["apps"] {
            let t = try table(apps, "apps")
            for id in t.keys { c.apps[id] = try parseApp(id, try table(t[id]!, "apps.\(id)")) }
        }

        if let projects = root["projects"] {
            guard let arr = projects.array else { throw ConfigError("'projects' must be an array: use [[projects]]") }
            for (i, p) in arr.enumerated() { c.projects.append(try parseProject(try table(p, "projects[\(i)]"))) }
        }

        c.modes = [:]
        if let modes = root["mode"] {
            let t = try table(modes, "mode")
            for name in t.keys {
                let mt = try table(t[name]!, "mode.\(name)")
                try checkKeys(mt, ["binding", "label", "sticky"], at: "mode.\(name)")
                if let s = mt["sticky"], try bool(s, "mode.\(name).sticky") { c.stickyModes.insert(name) }
                if let l = mt["label"] { c.modeLabels[name] = try string(l, "mode.\(name).label") }
                var bindings: [KeyCombo: String] = [:]
                var labels: [KeyCombo: String] = [:]
                if let b = mt["binding"] {
                    let bt = try table(b, "mode.\(name).binding")
                    for key in bt.keys {
                        guard let combo = KeyCombo(parsing: key) else {
                            throw ConfigError("mode.\(name).binding: bad key '\(key)'")
                        }
                        let at = "mode.\(name).binding.\(key)"
                        var v = bt[key]!
                        if let t = v.table {
                            // Long form: { run = '...', label = '...' }
                            try checkKeys(t, ["run", "label"], at: at)
                            guard let run = t["run"] else { throw ConfigError("\(at): missing 'run'") }
                            if let l = t["label"] { labels[combo] = try string(l, "\(at).label") }
                            v = run
                        }
                        let script: String
                        if let s = v.string {
                            script = s
                        } else if let a = v.array {
                            script = try a.map { try string($0, key) }.joined(separator: "; ")
                        } else {
                            throw ConfigError("\(at): expected a string, an array of strings or { run, label }")
                        }
                        // Fail on load, not on key press.
                        do { _ = try Command.parseScript(script) } catch {
                            throw ConfigError("\(at): \(error)")
                        }
                        bindings[combo] = script
                    }
                }
                c.modes[name] = bindings
                if !labels.isEmpty { c.bindingLabels[name] = labels }
            }
        }
        if c.modes["main"] == nil { c.modes["main"] = [:] }
        return c
    }

    private static func parseApp(_ id: String, _ t: TOMLTable) throws -> AppDef {
        let at = "apps.\(id)"
        try checkKeys(
            t, ["bundle-id", "args", "title", "workspace", "launch", "global-launch", "open-url", "global-open-url",
                "new-windows", "floating", "manage"],
            at: at)
        var a = AppDef(id: id)
        func str(_ k: String) throws -> String? { try t[k].map { try string($0, "\(at).\(k)") } }
        a.bundleID = try str("bundle-id")
        a.args = try str("args")
        a.title = try str("title")
        a.workspace = try str("workspace")
        a.launch = try str("launch")
        a.globalLaunch = try str("global-launch")
        a.openURL = try str("open-url")
        a.globalOpenURL = try str("global-open-url")
        if let nw = try str("new-windows") {
            guard let p = NewWindowPolicy(rawValue: nw) else {
                throw ConfigError("\(at).new-windows: expected 'unlinked' or 'active-project'")
            }
            a.newWindows = p
        }
        if let f = t["floating"] { a.floating = try bool(f, "\(at).floating") }
        if let m = t["manage"] { a.manage = try bool(m, "\(at).manage") }
        for p in [a.args, a.title].compactMap({ $0 }) {
            let probe = p.replacingOccurrences(of: "{project}", with: "x")
            if (try? NSRegularExpression(pattern: probe)) == nil { throw ConfigError("\(at): bad regex '\(p)'") }
        }
        return a
    }

    private static func parseProject(_ t: TOMLTable) throws -> ProjectDef {
        try checkKeys(t, ["name", "apps"], at: "projects")
        guard let name = t["name"]?.string else { throw ConfigError("every [[projects]] needs a name") }
        let at = "project '\(name)'"
        var p = ProjectDef(name: name)
        if let apps = t["apps"] {
            guard let arr = apps.array else { throw ConfigError("\(at): 'apps' must be an array") }
            for item in arr {
                if let s = item.string {
                    p.apps.append(ProjectAppRef(app: s))
                    continue
                }
                let it = try table(item, "\(at) apps")
                try checkKeys(it, ["app", "autostart", "workspace", "open"], at: "\(at) apps")
                guard let app = it["app"]?.string else { throw ConfigError("\(at): app entry without 'app'") }
                var ref = ProjectAppRef(app: app)
                if let v = it["autostart"] { ref.autostart = try bool(v, "\(at).\(app).autostart") }
                if let v = it["workspace"] { ref.workspace = try string(v, "\(at).\(app).workspace") }
                if let v = it["open"] {
                    guard let a = v.array else { throw ConfigError("\(at).\(app).open: expected an array") }
                    ref.open = try a.map { try string($0, "\(at).\(app).open") }
                }
                p.apps.append(ref)
            }
        }
        return p
    }

    // MARK: - Helpers

    private static func checkKeys(_ t: TOMLTable, _ allowed: Set<String>, at: String) throws {
        if let bad = t.keys.first(where: { !allowed.contains($0) }) {
            throw ConfigError("\(at): unknown key '\(bad)'")
        }
    }

    private static func table(_ v: TOMLValueConvertible, _ at: String) throws -> TOMLTable {
        guard let t = v.table else { throw ConfigError("\(at): expected a table") }
        return t
    }

    private static func string(_ v: TOMLValueConvertible, _ at: String) throws -> String {
        guard let s = v.string else { throw ConfigError("\(at): expected a string") }
        return s
    }

    private static func layoutKind(_ v: TOMLValueConvertible, _ at: String) throws -> LayoutKind {
        guard let k = LayoutKind(rawValue: try string(v, at)) else {
            throw ConfigError("\(at): expected 'maximized' or 'tiles'")
        }
        return k
    }

    private static func bool(_ v: TOMLValueConvertible, _ at: String) throws -> Bool {
        guard let b = v.bool else { throw ConfigError("\(at): expected true or false") }
        return b
    }

    private static func number(_ v: TOMLValueConvertible, _ at: String) throws -> Double {
        if let d = v.double { return d }
        if let i = v.int { return Double(i) }
        throw ConfigError("\(at): expected a number")
    }
}

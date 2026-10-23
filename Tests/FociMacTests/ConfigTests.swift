import FociCore
import Testing

@testable import FociMac

@MainActor
struct ConfigTests {
    @Test func defaultConfigParsesValidatesAndUsesKnownKeys() throws {
        let c = try TOMLConfigSource.parse(DefaultConfig.text)
        #expect(c.validate() == [])
        #expect(c.startAtLogin)
        #expect(c.projects.map(\.name) == ["p", "bil", "iam", "gc"])
        #expect(c.workspaces["x"] == .secondary)
        #expect(c.apps["chrome"]?.newWindows == .activeProject)
        #expect(c.project("bil")?.ref("dbeaver")?.autostart == false)
        #expect(c.browser == "chrome")
        #expect(c.apps["chrome"]?.openURL == #"open -a "Google Chrome" {url}"#)
        for (mode, bindings) in c.modes {
            for combo in bindings.keys {
                #expect(Hotkeys.keyCodes[combo.key] != nil || KeyCombo.tapKeys.contains(combo.key), "\(mode): \(combo)")
            }
        }
    }

    @Test func parsesAllForms() throws {
        let c = try TOMLConfigSource.parse(
            """
            gap = 8
            default-layout = 'tiles'
            [workspaces]
            w = { display = 'LG' }
            c = { layout = 'maximized', orientation = 'vertical' }
            x = '2'
            [apps.cursor]
            bundle-id = 'com.cursor'
            args = '--user-data-dir {project}'
            launch = 'cursor {open}'
            floating = true
            [[projects]]
            name = 'bil'
            apps = ['cursor', { app = 'cursor', autostart = false, workspace = 'c', open = ['~/a', '/b'] }]
            [mode.main.binding]
            alt-1 = ['project bil', 'workspace w']
            """)
        #expect(c.gap == 8)
        #expect(c.workspaces == ["w": .name("LG"), "c": .main, "x": .index(2)])
        #expect(c.defaultLayout == Layout(.tiles))
        #expect(c.workspaceLayouts == ["c": Layout(.maximized, orientation: .vertical)])
        #expect(c.apps["cursor"]?.floating == true)
        #expect(c.projects[0].apps[1] == ProjectAppRef(app: "cursor", autostart: false, workspace: "c", open: ["~/a", "/b"]))
        #expect(c.modes["main"]?[KeyCombo(modifiers: [.alt], key: "1")] == "project bil; workspace w")
    }

    @Test func rejectsTyposAndBadCommands() {
        #expect(throws: ConfigError.self) { try TOMLConfigSource.parse("[apps.x]\nbundle_id = 'a'") }
        #expect(throws: ConfigError.self) { try TOMLConfigSource.parse("[mode.main.binding]\nalt-1 = 'teleport'") }
        #expect(throws: ConfigError.self) { try TOMLConfigSource.parse("[apps.x]\ntitle = '(unclosed'") }
        #expect(throws: ConfigError.self) { try TOMLConfigSource.parse("gap = ") }
        #expect(throws: ConfigError.self) { try TOMLConfigSource.parse("default-layout = 'bsp'") }
    }

    /// These crash toml++ inside TOMLKit if they reach it.
    @Test func tableHeadersWithoutAKeyAreErrorsNotCrashes() throws {
        for bad in ["[[[ not toml", "gap = 1\n[=]", "[#]", "[[ .a]]", "[ \n", "["] {
            #expect(throws: ConfigError.self, "\(bad)") { try TOMLConfigSource.checkTableHeaders(bad) }
        }
        #expect(throws: ConfigError("line 3: expected a key in the table header")) {
            try TOMLConfigSource.checkTableHeaders("a = 1\n\n  [[[x]]]")
        }
        // A '[' in a value is not a header.
        for good in [
            "[apps.x]\n[[projects]]\n[ \"a b\" ]\n['c']\n[]", "leader = [\n  [1, 2],\n  [{ a = 1 }],\n]\n[t]",
            "s = '''\n[#\n'''", "s = \"\"\"\n[=\"\"\"\"\n[t]", "s = \"a\\\"[\"\n# [=\n[t]",
        ] {
            #expect(throws: Never.self, "\(good)") { try TOMLConfigSource.checkTableHeaders(good) }
        }
    }

    @Test func browserMustHaveGlobalOpenURL() throws {
        let c = try TOMLConfigSource.parse("browser = 'ff'\n[apps.ff]\nopen-url = 'open -a Firefox {url}'")
        #expect(c.validate() == ["browser: app 'ff' has no global-open-url command"])
        #expect(try TOMLConfigSource.parse("browser = 'ff'").validate() == ["browser: unknown app 'ff'"])
    }

    @Test func keyHintOptionsAndLabels() throws {
        let c = try TOMLConfigSource.parse(
            """
            key-hints-delay = 500
            [mode.main.binding]
            f20 = 'mode control'
            [mode.control]
            label = 'Foci'
            [mode.control.binding]
            w = { run = 'workspace w; mode main', label = 'web' }
            b = { run = ['balance', 'mode main'] }
            """)
        #expect(c.keyHints)
        #expect(c.keyHintsDelay == 0.5)
        #expect(c.modeLabels == ["control": "Foci"])
        #expect(c.modes["control"]?[KeyCombo(modifiers: [], key: "b")] == "balance; mode main")
        #expect(c.bindingLabels["control"] == [KeyCombo(modifiers: [], key: "w"): "web"])
        #expect(throws: ConfigError.self) { try TOMLConfigSource.parse("[mode.main.binding]\nx = { label = 'a' }") }
        #expect(throws: ConfigError.self) { try TOMLConfigSource.parse("[mode.main]\nlabel = 1") }
        #expect(throws: ConfigError.self) { try TOMLConfigSource.parse("key-hints-delay = -1") }
        #expect(try TOMLConfigSource.parse("key-hints = false").keyHints == false)
    }

    @Test func leaderStandsForEachLeaderKey() throws {
        let c = try TOMLConfigSource.parse(
            """
            leader = ['right-cmd', 'f20']
            [mode.main.binding]
            leader = 'mode control'
            [mode.control.binding]
            leader = { run = 'workspace-back-and-forth', label = 'last workspace', repeat = true }
            """)
        let keys = [KeyCombo(parsing: "right-cmd")!, KeyCombo(parsing: "f20")!]
        #expect(c.leaderKeys == keys)
        #expect(c.modes["main"] == [keys[0]: "mode control", keys[1]: "mode control"])
        #expect(c.bindingLabels["control"] == [keys[0]: "last workspace", keys[1]: "last workspace"])
        #expect(c.repeatKeys["control"] == Set(keys))
        #expect(try TOMLConfigSource.parse("leader = 'f20'").leaderKeys == [keys[1]])
        #expect(throws: ConfigError.self) { try TOMLConfigSource.parse("[mode.main.binding]\nleader = 'mode x'") }
        #expect(throws: ConfigError.self) { try TOMLConfigSource.parse("leader = ['leader']") }
        #expect(throws: ConfigError.self) {
            try TOMLConfigSource.parse("leader = 'f20'\n[mode.main.binding]\nleader = 'mode x'\nf20 = 'mode y'")
        }
        #expect(KeyHintPanel.keyLabel(.leader) == "Leader")
        #expect(KeyHintPanel.keyLabel(KeyCombo(parsing: "shift-backslash")!) == "|")
        #expect(KeyHintPanel.keyLabel(KeyHint(combo: KeyCombo(parsing: "a")!, label: "workspace", isGroup: false, range: "a-z")) == "a-z")
        #expect(KeyHintPanel.keyLabel(KeyCombo(parsing: "shift-w")!) == "⇧W")
    }

    @Test func workspaceTemplateBindsEveryLetterAndOneCharacterWorkspace() throws {
        let c = try TOMLConfigSource.parse(
            """
            [workspaces]
            1 = 'main'
            web = 'main'
            [mode.control.binding]
            '{workspace}' = 'workspace {workspace}'
            'shift-{workspace}' = { run = 'move-to-workspace --follow {workspace}', label = 'go to {workspace}' }
            x = 'focus next'
            """)
        func k(_ s: String) -> KeyCombo { KeyCombo(parsing: s)! }
        let control = c.modes["control"]!
        #expect(control.count == 27 * 2)
        #expect(control[k("a")] == "workspace a")
        #expect(control[k("1")] == "workspace 1")
        #expect(control[k("x")] == "focus next")
        #expect(control[k("shift-x")] == "move-to-workspace --follow x")
        #expect(control[k("web")] == nil)
        #expect(c.bindingLabels["control"]?[k("shift-x")] == "go to x")
    }

    @Test func repeatKeysAndTimeouts() throws {
        let c = try TOMLConfigSource.parse(
            """
            leader-timeout = 0
            repeat-timeout = 800
            [mode.control.binding]
            j = { run = 'focus next', repeat = true }
            k = { run = 'focus prev', repeat = false }
            """)
        #expect(c.leaderTimeout == 0)
        #expect(c.repeatTimeout == 0.8)
        #expect(c.repeatKeys["control"] == [KeyCombo(modifiers: [], key: "j")])
        let d = try TOMLConfigSource.parse("")
        #expect(d.leaderTimeout == 5 && d.repeatTimeout == 1 && d.keyHintsDelay == 0.3)
        #expect(throws: ConfigError.self) { try TOMLConfigSource.parse("repeat-timeout = 0") }
        #expect(throws: ConfigError.self) { try TOMLConfigSource.parse("leader-timeout = -1") }
        #expect(throws: ConfigError.self) {
            try TOMLConfigSource.parse("[mode.control.binding]\nj = { run = 'focus next', repeat = 1 }")
        }
    }

    @Test func modifierTaps() {
        var t = TapDetector()
        #expect(t.modifier("right-cmd", down: true, at: 0) == nil)
        #expect(t.modifier("right-cmd", down: false, at: 0.1) == "right-cmd")
        // Held too long.
        _ = t.modifier("right-cmd", down: true, at: 1)
        #expect(t.modifier("right-cmd", down: false, at: 2) == nil)
        // A shortcut: ⌘C.
        _ = t.modifier("right-cmd", down: true, at: 3)
        t.interrupt()
        #expect(t.modifier("right-cmd", down: false, at: 3.1) == nil)
        // A chord of modifiers.
        _ = t.modifier("right-cmd", down: true, at: 4)
        _ = t.modifier("left-shift", down: true, at: 4.05)
        #expect(t.modifier("left-shift", down: false, at: 4.1) == nil)
        #expect(t.modifier("right-cmd", down: false, at: 4.15) == nil)
        #expect(KeyHintPanel.keyLabel(KeyCombo(parsing: "right-cmd")!) == "⌘›")
    }

    @Test func menuBarStyle() throws {
        #expect(try TOMLConfigSource.parse("").menuBarStyle == .i3)
        #expect(try TOMLConfigSource.parse("menu-bar-style = 'text'").menuBarStyle == .text)
        #expect(throws: ConfigError.self) { try TOMLConfigSource.parse("menu-bar-style = 'fancy'") }
        #expect(MenuBarLabel.symbol("W", "square") == "w.square")
        #expect(MenuBarLabel.symbol("12", "square") == "12.square")
        #expect(MenuBarLabel.symbol("web", "square") == nil)
        #expect(MenuBarLabel.symbol("51", "square") == nil)
    }

    @Test func keyLabelsUseMacSymbols() {
        #expect(KeyHintPanel.keyLabel(KeyCombo(parsing: "shift-ctrl-a")!) == "⌃⇧A")
        #expect(KeyHintPanel.keyLabel(KeyCombo(parsing: "minus")!) == "-")
        #expect(KeyHintPanel.keyLabel(KeyCombo(parsing: "alt-left")!) == "⌥←")
        #expect(KeyHintPanel.keyLabel(KeyCombo(parsing: "f20")!) == "F20")
    }
}

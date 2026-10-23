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
                #expect(Hotkeys.keyCodes[combo.key] != nil, "\(mode): \(combo)")
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

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
}

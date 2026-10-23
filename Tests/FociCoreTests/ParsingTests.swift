import Testing

@testable import FociCore

struct ParsingTests {
    @Test func scriptSplitsOnSemicolonsAndExecTakesTheRest() throws {
        #expect(
            try Command.parseScript("workspace w; launch chrome;mode main")
                == [.workspace(.named("w")), .launch(app: "chrome"), .mode("main")])
        #expect(
            try Command.parseScript("mode main; exec open -a Slack; echo hi")
                == [.mode("main"), .exec("open -a Slack; echo hi")])
    }

    @Test func projectTargets() throws {
        #expect(try Command.parse("project --none") == .project(.none))
        #expect(try Command.parse("project next") == .project(.cycle(.next)))
        #expect(try Command.parse("project bil") == .project(.named("bil")))
        #expect(try Command.parse("link --active") == .link(nil))
        #expect(try Command.parse("move-to-workspace --follow x") == .moveToWorkspace("x", follow: true))
    }

    @Test func badCommandsAreRejected() {
        #expect(throws: Command.ParseError.self) { try Command.parse("teleport") }
        #expect(throws: Command.ParseError.self) { try Command.parse("focus up") }
        #expect(throws: Command.ParseError.self) { try Command.parse("unlink now") }
    }

    @Test func keyCombos() {
        #expect(KeyCombo(parsing: "ctrl-shift-P") == KeyCombo(modifiers: [.ctrl, .shift], key: "p"))
        #expect(KeyCombo(parsing: "f20") == KeyCombo(modifiers: [], key: "f20"))
        #expect(KeyCombo(parsing: "hyper-p") == nil)
        #expect(KeyCombo(parsing: "alt-") == nil)
        #expect(KeyCombo(parsing: "Right-Cmd") == KeyCombo(modifiers: [], key: "right-cmd"))
        #expect(KeyCombo(parsing: "right-cmd")?.description == "right-cmd")
        #expect(KeyCombo(parsing: "shift-right-cmd") == nil)
    }

    @Test func displaySpecs() {
        let displays = [Display.right, Display.left]
        #expect(DisplaySpec(parsing: "main").resolve(in: displays)?.id == Display.left.id)
        #expect(DisplaySpec(parsing: "secondary").resolve(in: displays)?.id == Display.right.id)
        #expect(DisplaySpec(parsing: "2").resolve(in: displays)?.id == Display.right.id)
        #expect(DisplaySpec(parsing: "lcd").resolve(in: displays)?.id == Display.right.id)
    }

    @Test func linkerPrefersPersonalDefinitionForUnmatchedWindows() {
        var c = Config.sample
        var personal = AppDef(id: "chrome-personal", bundleID: "com.google.Chrome")
        personal.workspace = "p"
        c.apps["chrome-personal"] = personal
        let w = WindowFacts(
            id: WindowID(1), pid: 1, bundleID: "com.google.Chrome", appName: "Chrome", appArgs: "", title: "Gmail",
            frame: Rect(x: 0, y: 0, width: 1, height: 1))
        #expect(Linker(config: c).match(w).app?.id == "chrome-personal")
    }

    @Test func validationReportsAmbiguousWholeAppDefinitions() {
        var c = Config.sample
        c.projects[0].apps.append(ProjectAppRef(app: "slack"))
        c.projects[1].apps.append(ProjectAppRef(app: "slack"))
        c.projects[1].apps.append(ProjectAppRef(app: "nope"))
        #expect(c.validate().count == 2)
    }

    @Test func keyHintsSortKeysBeforeGroupsAndDropModeMain() {
        var c = Config()
        func k(_ s: String) -> KeyCombo { KeyCombo(parsing: s)! }
        c.modes["control"] = [
            k("slash"): "mode project", k("shift-w"): "move-to-workspace w; mode main", k("w"): "workspace w; mode main",
            k("esc"): "mode main", k("minus"): "resize -50; mode project", k("a"): "workspace a; mode main",
        ]
        c.modes["project"] = [:]
        c.modeLabels["project"] = "Link window"
        c.bindingLabels["control"] = [k("a"): "apps"]
        #expect(c.keyHints(for: "control") == [
            KeyHint(combo: k("a"), label: "apps", isGroup: false),
            KeyHint(combo: k("w"), label: "workspace w", isGroup: false),
            KeyHint(combo: k("shift-w"), label: "move-to-workspace w", isGroup: false),
            KeyHint(combo: k("esc"), label: "close", isGroup: false),
            KeyHint(combo: k("minus"), label: "resize -50 +Link window", isGroup: false),
            KeyHint(combo: k("slash"), label: "Link window", isGroup: true),
        ])
        #expect(c.keyHints(for: "nope") == [])
    }

    @Test func keyHintsShowTheLeaderKeysAsOneRow() {
        var c = Config()
        func k(_ s: String) -> KeyCombo { KeyCombo(parsing: s)! }
        c.leaderKeys = [k("right-cmd"), k("f20")]
        c.modes["control"] = [k("right-cmd"): "workspace-back-and-forth", k("f20"): "workspace-back-and-forth"]
        c.bindingLabels["control"] = [k("right-cmd"): "last", k("f20"): "last"]
        #expect(c.keyHints(for: "control") == [KeyHint(combo: .leader, label: "last", isGroup: false)])
        // Different scripts: each key keeps its row.
        c.modes["control"]![k("f20")] = "focus next"
        #expect(c.keyHints(for: "control").map(\.combo) == [k("f20"), k("right-cmd")])
    }
}

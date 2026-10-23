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
}

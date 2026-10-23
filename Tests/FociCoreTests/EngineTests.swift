import Foundation
import Testing

@testable import FociCore

@MainActor
struct EngineTests {
    @Test func newWindowsAreLinkedByRulesAndPlacedOnTheAppWorkspace() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "bil - Google Chrome")
        h.ws.open(2, bundle: "net.kovidgoyal.kitty", args: "kitty --instance-group iam")
        h.ws.open(3, bundle: "com.google.Chrome", title: "Inbox - Gmail")
        h.ws.open(4, bundle: "com.apple.finder")
        h.engine.refresh()

        #expect(h.record(1) == WindowRecord(owner: "bil", workspace: "w", app: "chrome", seq: 0))
        #expect(h.record(2)?.owner == "iam")
        #expect(h.record(2)?.workspace == "x")
        #expect(h.record(3)?.owner == nil)
        #expect(h.record(3)?.workspace == "w")
        #expect(h.record(4)?.owner == nil)
        #expect(h.record(4)?.workspace == h.engine.focusedWorkspace)
    }

    @Test func eachDisplayShowsOneWorkspace() {
        let h = Harness()
        h.engine.refresh()
        #expect(h.engine.state.activeWorkspace == [DisplayID(1): "c", DisplayID(2): "s"])
        #expect(h.engine.focusedWorkspace == "c")
    }

    @Test func switchingProjectHidesOtherProjectsAndKeepsUnlinkedWindows() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "bil - Google Chrome")
        h.ws.open(2, bundle: "com.google.Chrome", title: "iam - Google Chrome")
        h.ws.open(3, bundle: "com.google.Chrome", title: "Personal")
        h.engine.run("workspace w; project bil")

        #expect(h.visible(1))
        #expect(!h.visible(2))
        #expect(h.visible(3))
        #expect(h.ws.frame(1) == Display.left.visibleFrame)
        #expect(h.ws.frame(3) == Display.left.visibleFrame)
        // Parked in the bottom-left corner: the laptop is to the right of the main display.
        #expect(h.ws.frame(2) == Rect(x: -799, y: 1439, width: 800, height: 600))

        h.engine.run("project iam")
        #expect(!h.visible(1))
        #expect(h.visible(2))
        #expect(h.visible(3))
        #expect(h.ws.frame(2) == Display.left.visibleFrame)
    }

    @Test func projectSwitchAppliesToBothDisplays() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "bil - Google Chrome")
        h.ws.open(2, bundle: "net.kovidgoyal.kitty", args: "kitty --instance-group bil")
        h.ws.open(3, bundle: "net.kovidgoyal.kitty", args: "kitty --instance-group iam")
        h.engine.run("workspace x; workspace w; project bil")
        #expect(h.visible(1) && h.visible(2) && !h.visible(3))
        #expect(h.ws.frame(2) == Display.right.visibleFrame)

        h.engine.run("project iam")
        #expect(!h.visible(1) && !h.visible(2) && h.visible(3))
        // The laptop has no right neighbour: park in its bottom-right corner.
        #expect(h.ws.frame(2).x == Display.right.frame.maxX - 1)
    }

    @Test func workspaceSwitchOnlyChangesItsDisplay() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "Personal")
        h.ws.open(2, bundle: "com.tinyspeck.slackmacgap")
        h.engine.run("workspace w")
        #expect(h.visible(1) && h.visible(2))
        h.engine.run("workspace c")
        #expect(!h.visible(1) && h.visible(2))
        h.engine.run("workspace-back-and-forth")
        #expect(h.engine.focusedWorkspace == "w")
        #expect(h.visible(1))
    }

    @Test func focusIsRestoredPerProjectAndWorkspace() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "bil - Google Chrome")
        h.ws.open(2, bundle: "com.google.Chrome", title: "bil - Google Chrome")
        h.ws.open(3, bundle: "com.google.Chrome", title: "iam - Google Chrome")
        h.engine.run("workspace w; project bil")
        #expect(h.ws.focused == WindowID(1))
        h.engine.run("focus next")
        #expect(h.ws.focused == WindowID(2))
        h.engine.run("project iam")
        #expect(h.ws.focused == WindowID(3))
        h.engine.run("project-back-and-forth")
        #expect(h.engine.activeProject == "bil")
        #expect(h.ws.focused == WindowID(2))
    }

    @Test func focusingAHiddenWindowSwitchesToItsProjectAndWorkspace() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "bil - Google Chrome")
        h.ws.open(2, bundle: "net.kovidgoyal.kitty", args: "kitty --instance-group iam")
        h.engine.run("workspace w; project bil")

        h.ws.focused = WindowID(2)  // Cmd-Tab to iam's kitty
        h.engine.refresh()
        #expect(h.engine.activeProject == "iam")
        #expect(h.engine.focusedWorkspace == "x")
        #expect(h.visible(2) && !h.visible(1))
    }

    @Test func aStaleFocusOnAParkedWindowDoesNotSwitchBack() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "bil - Google Chrome")
        h.engine.run("workspace w; project bil")
        h.engine.run("project iam")  // nothing to focus: macOS keeps window 1 focused although parked
        h.engine.refresh()
        #expect(h.engine.activeProject == "iam")
    }

    @Test func linkAndUnlinkByHand() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "Personal")
        h.engine.run("workspace w; project bil")
        h.ws.focused = WindowID(1)
        h.engine.refresh()

        h.engine.run("link --active")
        #expect(h.record(1)?.owner == "bil")
        h.engine.run("project iam")
        #expect(!h.visible(1))

        h.engine.run("project bil")
        h.ws.focused = WindowID(1)
        h.engine.run("unlink")
        #expect(h.record(1)?.owner == nil)
        #expect(h.record(1)?.manual == true)
        h.engine.run("project iam")
        #expect(h.visible(1))
    }

    @Test func manualUnlinkWinsOverTitleRules() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "bil - Google Chrome")
        h.engine.run("workspace w; project bil")
        h.ws.focused = WindowID(1)
        h.engine.run("unlink")
        h.engine.refresh()
        #expect(h.record(1)?.owner == nil)
    }

    @Test func renamedWindowGetsLinkedByTitleRule() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "New Tab")
        h.engine.refresh()
        #expect(h.record(1)?.owner == nil)
        h.ws.windowList[0].title = "iam - Google Chrome"
        h.engine.refresh()
        #expect(h.record(1)?.owner == "iam")
    }

    @Test func autostartLaunchesMissingAppOnItsWorkspaceAndLinksTheNewWindow() {
        let h = Harness()
        h.engine.run("project bil")
        // cursor lives on c, the focused workspace
        #expect(h.launcher.commands.map(\.0) == [#"cursor --user-data-dir ~/.cursor-projects/bil "$HOME/src/bil api""#])
        #expect(h.launcher.commands[0].1 == ["FOCI_PROJECT": "bil"])

        h.engine.run("workspace w; workspace c")
        #expect(h.launcher.commands.count == 1)  // pending launch is not repeated

        h.ws.open(7, bundle: "com.todesktop.cursor", args: "Cursor")  // args don't tell the project
        h.engine.refresh()
        #expect(h.record(7)?.owner == "bil")
        #expect(h.record(7)?.workspace == "c")
    }

    @Test func launchFocusesExistingWindowOrStartsTheApp() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "bil - Google Chrome")
        h.engine.run("project bil; workspace x")
        h.engine.run("launch chrome")
        #expect(h.engine.focusedWorkspace == "w")
        #expect(h.ws.focused == WindowID(1))

        h.engine.run("project iam; launch chrome")
        #expect(h.launcher.commands.last?.0 == "open -na 'Google Chrome' --args --new-window")

        h.engine.run("project --none; launch chrome")
        #expect(h.launcher.commands.last?.0 == "open -a 'Google Chrome'")
    }

    @Test func moveWindowToWorkspace() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "Personal")
        h.engine.run("workspace w")
        h.ws.focused = WindowID(1)
        h.engine.run("move-to-workspace x")
        #expect(h.record(1)?.workspace == "x")
        #expect(!h.visible(1))  // s, not x, is active on the right display
        h.engine.run("workspace x")
        #expect(h.ws.frame(1) == Display.right.visibleFrame)
        h.engine.run("move-to-workspace --follow c")
        #expect(h.engine.focusedWorkspace == "c")
        #expect(h.ws.frame(1) == Display.left.visibleFrame)
    }

    @Test func moveWorkspaceToOtherDisplay() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "Personal")
        h.engine.run("workspace w; move-workspace-to-display next")
        #expect(h.engine.display(of: "w").id == Display.right.id)
        #expect(h.engine.state.activeWorkspace[Display.right.id] == "w")
        #expect(h.engine.state.activeWorkspace[Display.left.id] == "c")
        #expect(h.ws.frame(1) == Display.right.visibleFrame)
    }

    @Test func floatingWindowKeepsItsFrameAcrossSwitches() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "bil - Google Chrome")
        h.engine.run("workspace w; project bil")
        h.ws.focused = WindowID(1)
        h.engine.run("float")
        let moved = Rect(x: 300, y: 200, width: 500, height: 400)
        h.ws.setFrame(WindowID(1), moved)  // the user drags it
        h.engine.refresh()
        h.engine.run("project iam; project bil")
        #expect(h.ws.frame(1) == moved)
    }

    @Test func stateSurvivesRestart() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "Personal")
        h.engine.run("workspace w; project bil")
        h.ws.focused = WindowID(1)
        h.engine.run("link iam")

        let h2 = Harness(ws: h.ws, state: h.store.state)
        h2.engine.refresh()
        #expect(h2.engine.activeProject == "bil")
        #expect(h2.record(1)?.owner == "iam")
        #expect(!h2.visible(1))
    }

    @Test func restoreAllPutsParkedWindowsBackOnScreen() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "bil - Google Chrome")
        h.engine.run("project iam")
        #expect(!Planner(displays: h.ws.displayList, gap: 0).isOnScreen(h.ws.frame(1)))
        h.engine.restoreAll()
        #expect(h.ws.frame(1) == Display.left.visibleFrame)
    }

    @Test func projectsRemovedFromConfigReleaseTheirWindows() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "bil - Google Chrome")
        h.engine.run("project bil")
        var c = Config.sample
        c.projects.removeAll { $0.name == "bil" }
        let h2 = Harness(config: c, ws: h.ws, state: h.store.state)
        h2.engine.refresh()
        #expect(h2.engine.activeProject == nil)
        #expect(h2.record(1)?.owner == nil)
    }
}

@MainActor
struct FrozenWindowTests {
    @Test func minimizedWindowsKeepTheirLinkAndAreNotMoved() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "Personal")
        h.engine.run("workspace w; project bil")
        h.ws.focused = WindowID(1)
        h.engine.run("link bil")
        h.ws.windowList[0].isFrozen = true
        let frame = h.ws.frame(1)
        h.engine.run("project iam")
        #expect(h.record(1)?.owner == "bil")
        #expect(h.ws.frame(1) == frame)
        h.ws.windowList[0].isFrozen = false
        h.engine.refresh()
        #expect(!Planner(displays: h.ws.displayList, gap: 0).isOnScreen(h.ws.frame(1)))
    }
}

@MainActor
struct StartupTests {
    @Test func focusReturningAfterLaunchDoesNotSwitchProject() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "bil - Google Chrome")
        h.engine.run("project iam")
        let h2 = Harness(ws: h.ws, state: h.store.state)
        h.ws.focused = nil  // Foci is frontmost right after launch
        h2.engine.refresh()
        h.ws.focused = WindowID(1)  // focus goes back to the previous app
        h2.engine.refresh()
        #expect(h2.engine.activeProject == "iam")
    }
}

@MainActor
struct TilingTests {
    /// Three bil Chrome windows on w, tiled.
    func tiled(gap: Double = 0) -> Harness {
        var c = Config.sample
        c.gap = gap
        let h = Harness(config: c)
        for i: UInt32 in 1...3 { h.ws.open(i, bundle: "com.google.Chrome", title: "bil - Google Chrome") }
        h.engine.run("workspace w; project bil; layout tiles")
        return h
    }

    @Test func tilesSplitTheDisplaySideBySideInOrder() {
        let h = tiled()
        let a = Display.left.visibleFrame
        let w = a.width / 3
        #expect(h.ws.frame(1) == Rect(x: 0, y: a.y, width: w, height: a.height))
        #expect(h.ws.frame(2) == Rect(x: w, y: a.y, width: w, height: a.height))
        #expect(h.ws.frame(3) == Rect(x: 2 * w, y: a.y, width: w, height: a.height))
    }

    @Test func gapsSurroundAndSeparateTiles() {
        let h = tiled(gap: 10)
        let a = Display.left.visibleFrame
        let w = (a.width - 20 - 20) / 3
        #expect(h.ws.frame(1) == Rect(x: 10, y: a.y + 10, width: w, height: a.height - 20))
        #expect(h.ws.frame(2).x == 10 + w + 10)
        #expect(h.ws.frame(3).maxX == a.maxX - 10)
    }

    @Test func toggleOrientationStacksWindows() {
        let h = tiled()
        h.engine.run("layout toggle-orientation")
        let a = Display.left.visibleFrame
        #expect(h.ws.frame(1) == Rect(x: 0, y: a.y, width: a.width, height: a.height / 3))
        #expect(h.ws.frame(3).maxY == a.maxY)
    }

    @Test func moveSwapsWithNeighbour() {
        let h = tiled()
        h.ws.focused = WindowID(1)
        h.engine.run("move next")
        #expect(h.engine.visibleWindows(in: "w") == [WindowID(2), WindowID(1), WindowID(3)])
        #expect(h.ws.frame(2).x == 0)
        #expect(h.ws.focused == WindowID(1))
    }

    @Test func resizeGrowsTheFocusedTileByPointsAndBalanceUndoesIt() {
        let h = tiled()
        let before = h.ws.frame(2).width
        h.ws.focused = WindowID(2)
        h.engine.run("resize +120")
        #expect(abs(h.ws.frame(2).width - (before + 120)) < 0.001)
        #expect(abs(h.ws.frame(1).width - (before - 60)) < 0.001)
        #expect(abs(h.ws.frame(3).maxX - Display.left.visibleFrame.maxX) < 0.001)
        h.engine.run("balance")
        #expect(abs(h.ws.frame(2).width - before) < 0.001)
    }

    @Test func floatingWindowsStayOutOfTheTiles() {
        let h = tiled()
        h.ws.focused = WindowID(3)
        h.engine.run("float")
        #expect(h.ws.frame(1).width == Display.left.visibleFrame.width / 2)
    }

    @Test func layoutIsRememberedPerProject() {
        let h = tiled()
        h.ws.open(9, bundle: "com.google.Chrome", title: "iam - Google Chrome")
        h.ws.open(10, bundle: "com.google.Chrome", title: "iam - Google Chrome")
        h.engine.run("project iam")
        #expect(h.engine.layout(of: "w").kind == .maximized)
        #expect(h.ws.frame(9) == Display.left.visibleFrame)
        h.engine.run("project bil")
        #expect(h.engine.layout(of: "w").kind == .tiles)
        #expect(h.ws.frame(1).width == Display.left.visibleFrame.width / 3)
    }

    @Test func configSetsTheInitialLayout() {
        var c = Config.sample
        c.workspaceLayouts["w"] = Layout(.tiles)
        let h = Harness(config: c)
        h.ws.open(1, bundle: "com.google.Chrome", title: "Personal")
        h.ws.open(2, bundle: "com.google.Chrome", title: "Gmail")
        h.engine.run("workspace w")
        #expect(h.ws.frame(1).width == Display.left.visibleFrame.width / 2)
    }

    @Test func oldStateFilesWithoutNewKeysStillLoad() throws {
        let json = #"{"activeProject":"bil","windows":{"7":{"workspace":"w","owner":"bil","seq":3}}}"#
        let s = try JSONDecoder().decode(State.self, from: Data(json.utf8))
        #expect(s.activeProject == "bil")
        #expect(s.windows[WindowID(7)]?.weight == 1)
        #expect(s.layouts == [:])
    }
}

@MainActor
struct TargetWindowTests {
    @Test func commandsActOnAnExplicitWindowEvenWhenHidden() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "bil - Google Chrome")
        h.ws.open(2, bundle: "com.google.Chrome", title: "Personal")
        h.engine.run("workspace w; project bil")
        h.ws.focused = WindowID(1)
        h.engine.run("project iam")  // window 1 is hidden now, window 2 still shown

        h.engine.run("move-to-workspace c", window: WindowID(1))
        #expect(h.record(1)?.workspace == "c")
        h.engine.run("unlink", window: WindowID(2))
        #expect(h.record(2)?.manual == true)

        h.engine.run("reveal", window: WindowID(1))
        #expect(h.engine.activeProject == "bil")
        #expect(h.engine.focusedWorkspace == "c")
        #expect(h.ws.focused == WindowID(1))
    }

    @Test func windowListIsGroupedByWorkspace() {
        let h = Harness()
        h.ws.open(1, bundle: "com.tinyspeck.slackmacgap")
        h.ws.open(2, bundle: "com.google.Chrome", title: "Personal")
        h.engine.refresh()
        #expect(h.engine.windowList().map(\.record.workspace) == ["s", "w"])
    }

    @Test func submenusAreOneShotWithBreadcrumbsAndBuiltInKeys() {
        var config = Config.sample
        config.modes["control"] = ["m": "mode move", "minus": "resize -50; mode resize", "w": "workspace w"]
            .reduce(into: [:]) { $0[KeyCombo(parsing: $1.key)!] = $1.value }
        config.modes["move"] = [KeyCombo(parsing: "w")!: "move-to-workspace w"]
        config.modes["resize"] = [KeyCombo(parsing: "minus")!: "resize -50"]
        config.stickyModes = ["resize"]
        config.modeLabels = ["control": "Foci", "move": "Move"]
        let h = Harness(config: config)
        h.engine.refresh()
        func press(_ key: String) { h.engine.press(h.engine.bindings[KeyCombo(parsing: key)!]!) }

        h.engine.run("mode control")
        press("w")
        #expect(h.engine.focusedWorkspace == "w")
        #expect(h.engine.mode == "main")

        h.engine.run("mode control")
        press("m")
        #expect(h.engine.mode == "move")
        #expect(h.engine.modeTitle == "Foci › Move")
        #expect(h.engine.keyHints.contains(KeyHint(combo: KeyCombo(parsing: "backspace")!, label: "back", isGroup: false)))
        press("backspace")
        #expect(h.engine.modePath == ["control"])
        press("esc")
        #expect(h.engine.mode == "main")

        h.engine.run("mode control")
        press("minus")
        press("minus")
        #expect(h.engine.mode == "resize")
        press("backspace")
        #expect(h.engine.mode == "control")
        #expect(h.engine.bindings[KeyCombo(parsing: "backspace")!] == "mode main")
    }
}

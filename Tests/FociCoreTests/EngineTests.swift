import Foundation
import Testing

@testable import FociCore

@MainActor
struct EngineTests {
    @Test func newWindowsAreLinkedByRulesAndPlacedOnTheAppWorkspace() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "work - Google Chrome")
        h.ws.open(2, bundle: "net.kovidgoyal.kitty", args: "kitty --instance-group pet")
        h.ws.open(3, bundle: "com.google.Chrome", title: "Inbox - Gmail")
        h.ws.open(4, bundle: "com.apple.finder")
        h.engine.refresh()

        #expect(h.record(1) == WindowRecord(owner: "work", workspace: "w", app: "chrome", seq: 0))
        #expect(h.record(2)?.owner == "pet")
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
        h.ws.open(1, bundle: "com.google.Chrome", title: "work - Google Chrome")
        h.ws.open(2, bundle: "com.google.Chrome", title: "pet - Google Chrome")
        h.ws.open(3, bundle: "com.google.Chrome", title: "Personal")
        h.engine.run("workspace w; project work")

        #expect(h.visible(1))
        #expect(!h.visible(2))
        #expect(h.visible(3))
        #expect(h.ws.frame(1) == Display.left.visibleFrame)
        #expect(h.ws.frame(3) == Display.left.visibleFrame)
        // Parked in the bottom-left corner: the laptop is to the right of the main display.
        #expect(h.ws.frame(2) == Rect(x: -799, y: 1439, width: 800, height: 600))

        h.engine.run("project pet")
        #expect(!h.visible(1))
        #expect(h.visible(2))
        #expect(h.visible(3))
        #expect(h.ws.frame(2) == Display.left.visibleFrame)
    }

    @Test func projectSwitchAppliesToBothDisplays() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "work - Google Chrome")
        h.ws.open(2, bundle: "net.kovidgoyal.kitty", args: "kitty --instance-group work")
        h.ws.open(3, bundle: "net.kovidgoyal.kitty", args: "kitty --instance-group pet")
        h.engine.run("workspace x; workspace w; project work")
        #expect(h.visible(1) && h.visible(2) && !h.visible(3))
        #expect(h.ws.frame(2) == Display.right.visibleFrame)

        h.engine.run("project pet")
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
        h.ws.open(1, bundle: "com.google.Chrome", title: "work - Google Chrome")
        h.ws.open(2, bundle: "com.google.Chrome", title: "work - Google Chrome")
        h.ws.open(3, bundle: "com.google.Chrome", title: "pet - Google Chrome")
        h.engine.run("workspace w; project work")
        #expect(h.ws.focused == WindowID(1))
        h.engine.run("focus next")
        #expect(h.ws.focused == WindowID(2))
        h.engine.run("project pet")
        #expect(h.ws.focused == WindowID(3))
        h.engine.run("project-back-and-forth")
        #expect(h.engine.activeProject == "work")
        #expect(h.ws.focused == WindowID(2))
    }

    @Test func eachProjectGetsBackItsWorkspacesAndWindow() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "work - Google Chrome")
        h.ws.open(2, bundle: "net.kovidgoyal.kitty", args: "kitty --instance-group work")
        h.ws.open(3, bundle: "com.google.Chrome", title: "pet - Google Chrome")
        h.engine.run("project work; workspace o; workspace x")
        h.engine.run("project pet; workspace w; workspace s")
        #expect(h.engine.state.activeWorkspace == [DisplayID(1): "w", DisplayID(2): "s"])

        h.engine.run("project work")
        #expect(h.engine.state.activeWorkspace == [DisplayID(1): "o", DisplayID(2): "x"])
        #expect(h.engine.focusedWorkspace == "x")
        #expect(h.ws.focused == WindowID(2))

        h.engine.run("project pet")
        #expect(h.engine.state.activeWorkspace == [DisplayID(1): "w", DisplayID(2): "s"])
        #expect(h.engine.focusedWorkspace == "s")
        h.engine.run("workspace w")
        #expect(h.ws.focused == WindowID(3))
    }

    @Test func focusingAHiddenWindowSwitchesToItsProjectAndWorkspace() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "work - Google Chrome")
        h.ws.open(2, bundle: "net.kovidgoyal.kitty", args: "kitty --instance-group pet")
        h.engine.run("workspace w; project work")

        h.ws.focused = WindowID(2)  // Cmd-Tab to pet's kitty
        h.engine.refresh()
        #expect(h.engine.activeProject == "pet")
        #expect(h.engine.focusedWorkspace == "x")
        #expect(h.visible(2) && !h.visible(1))
    }

    @Test func aStaleFocusOnAParkedWindowDoesNotSwitchBack() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "work - Google Chrome")
        h.engine.run("workspace w; project work")
        h.engine.run("project pet")  // nothing to focus: macOS keeps window 1 focused although parked
        h.engine.refresh()
        #expect(h.engine.activeProject == "pet")
    }

    @Test func linkAndUnlinkByHand() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "Personal")
        h.engine.run("workspace w; project work")
        h.ws.focused = WindowID(1)
        h.engine.refresh()

        h.engine.run("link --active")
        #expect(h.record(1)?.owner == "work")
        h.engine.run("project pet")
        #expect(!h.visible(1))

        h.engine.run("project work")
        h.ws.focused = WindowID(1)
        h.engine.run("unlink")
        #expect(h.record(1)?.owner == nil)
        #expect(h.record(1)?.manual == true)
        h.engine.run("project pet")
        #expect(h.visible(1))
    }

    @Test func linkWithFollowSwitchesToTheProjectWithTheWindow() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "Personal")
        h.ws.open(2, bundle: "com.google.Chrome", title: "work - Google Chrome")
        h.engine.run("workspace w; project work")
        h.ws.focused = WindowID(1)
        h.engine.refresh()

        h.engine.run("link --follow pet")
        #expect(h.record(1)?.owner == "pet")
        #expect(h.engine.activeProject == "pet")
        #expect(h.visible(1))
        #expect(!h.visible(2))
        #expect(h.ws.focused == WindowID(1))
    }

    @Test func manualUnlinkWinsOverTitleRules() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "work - Google Chrome")
        h.engine.run("workspace w; project work")
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
        h.ws.windowList[0].title = "pet - Google Chrome"
        h.engine.refresh()
        #expect(h.record(1)?.owner == "pet")
    }

    @Test func autostartLaunchesMissingAppOnItsWorkspaceAndLinksTheNewWindow() {
        let h = Harness()
        h.engine.run("project work")
        // cursor lives on c, the focused workspace
        #expect(h.launcher.commands.map(\.0) == [#"cursor --user-data-dir ~/.cursor-projects/work "$HOME/src/work api""#])
        #expect(h.launcher.commands[0].1 == ["FOCI_PROJECT": "work"])

        h.engine.run("workspace w; workspace c")
        #expect(h.launcher.commands.count == 1)  // pending launch is not repeated

        h.ws.open(7, bundle: "com.todesktop.cursor", args: "Cursor")  // args don't tell the project
        h.engine.refresh()
        #expect(h.record(7)?.owner == "work")
        #expect(h.record(7)?.workspace == "c")
    }

    @Test func launchFocusesExistingWindowOrStartsTheApp() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "work - Google Chrome")
        h.engine.run("project work; workspace x")
        h.engine.run("launch chrome")
        #expect(h.engine.focusedWorkspace == "w")
        #expect(h.ws.focused == WindowID(1))

        h.engine.run("project pet; launch chrome")
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

    @Test func moveWindowToOtherDisplay() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "Personal")
        h.engine.run("workspace w")
        h.ws.focused = WindowID(1)
        h.engine.run("move-to-display next")
        #expect(h.record(1)?.workspace == "s")
        #expect(h.ws.frame(1) == Display.right.visibleFrame)
        #expect(h.engine.focusedWorkspace == "w")
        h.ws.focused = WindowID(1)
        h.engine.run("move-to-display --follow prev")
        #expect(h.record(1)?.workspace == "w")
        #expect(h.engine.focusedWorkspace == "w")
        h.engine.run("focus-display next")
        h.ws.focused = WindowID(1)
        h.engine.run("focus-display prev; move-to-display --follow next")
        #expect(h.engine.focusedWorkspace == "s")
        #expect(h.ws.frame(1) == Display.right.visibleFrame)
        #expect(throws: Command.ParseError.self) { try Command.parse("move-to-display") }
        #expect(throws: Command.ParseError.self) { try Command.parse("focus-display") }
        #expect((try? Command.parse("focus-display ext 1")) == .focusDisplay(.spec(.name("ext 1"))))
    }

    @Test func focusAppCyclesTheAppsWindowsAcrossWorkspaces() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "work - Google Chrome")
        h.ws.open(2, bundle: "com.google.Chrome", title: "pet - Google Chrome")
        h.ws.open(3, bundle: "com.google.Chrome", title: "Personal")
        h.ws.open(4, bundle: "net.kovidgoyal.kitty", args: "kitty --instance-group work")
        h.engine.run("workspace w; project work")
        h.ws.focused = WindowID(3)
        h.engine.run("move-to-workspace c")
        h.ws.focused = WindowID(1)
        h.engine.run("focus-app next")
        #expect(h.ws.focused == WindowID(3))  // pet's window is skipped
        #expect(h.engine.focusedWorkspace == "c")
        #expect(h.visible(3))
        h.engine.run("focus-app next")
        #expect(h.ws.focused == WindowID(1))
        #expect(h.engine.focusedWorkspace == "w")
        h.engine.run("focus-app prev")
        #expect(h.ws.focused == WindowID(3))
        h.ws.focused = WindowID(4)
        h.engine.run("focus-app next")
        #expect(h.ws.focused == WindowID(4))
    }

    @Test func focusBackWalksTheHistoryAndCommitsWhenTheRepeatEnds() {
        var c = Config.sample
        c.focusHistory = 2
        c.modes["control"] = [KeyCombo(parsing: "space")!: "focus-back"]
        c.repeatKeys["control"] = [KeyCombo(parsing: "space")!]
        let h = Harness(config: c)
        h.ws.open(1, bundle: "com.google.Chrome", title: "work - Google Chrome")
        h.ws.open(2, bundle: "net.kovidgoyal.kitty", args: "kitty --instance-group pet")
        h.ws.open(3, bundle: "com.google.Chrome", title: "Personal")
        h.ws.open(4, bundle: "com.google.Chrome", title: "Other")
        h.engine.run("workspace w; project work")
        for id: UInt32 in [4, 3, 2] {  // Cmd-Tab: 4, then 3, then pet's kitty
            h.ws.focused = WindowID(id)
            h.engine.refresh()
        }
        let space = KeyCombo(parsing: "space")!
        func leaderSpace() {
            h.engine.run("mode control")
            h.engine.press(space)
        }
        // Leader space: the previous window.
        leaderSpace()
        #expect(h.ws.focused == WindowID(3))
        h.engine.refresh()  // the focus reported late is not a user action
        // Space again while repeating: one further back.
        h.engine.press(space)
        #expect(h.ws.focused == WindowID(4))
        // The history is 2 deep: the focus stays.
        h.engine.press(space)
        #expect(h.ws.focused == WindowID(4))
        h.engine.run("mode main")  // the repeat timed out on window 4
        // Leader space after the pause: back to where it started.
        leaderSpace()
        #expect(h.ws.focused == WindowID(2))
        #expect(h.engine.activeProject == "pet")
        h.engine.run("mode main")
        leaderSpace()
        #expect(h.ws.focused == WindowID(4))
        // A closed window is skipped.
        h.engine.run("mode main")
        h.ws.windowList.removeAll { $0.id == WindowID(2) }
        h.engine.refresh()
        leaderSpace()
        #expect(h.ws.focused == WindowID(3))
    }

    @Test func focusBackShowsEachWindowOnce() {
        var c = Config.sample
        c.modes["control"] = [KeyCombo(parsing: "space")!: "focus-back"]
        c.repeatKeys["control"] = [KeyCombo(parsing: "space")!]
        let h = Harness(config: c)
        for id: UInt32 in 1...4 { h.ws.open(id, bundle: "com.google.Chrome", title: "Personal \(id)") }
        h.engine.run("workspace w")
        // A B C B D B A by hand.
        for id: UInt32 in [1, 2, 3, 2, 4, 2, 1] {
            h.ws.focused = WindowID(id)
            h.engine.refresh()
        }
        let space = KeyCombo(parsing: "space")!
        h.engine.run("mode control")
        var seen: [WindowID?] = []
        for _ in 0..<4 {
            h.engine.press(space)
            seen.append(h.ws.focused)
        }
        // B D C, then the history is used up: C stays.
        #expect(seen == [2, 4, 3, 3].map { WindowID($0) })
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
        h.ws.open(1, bundle: "com.google.Chrome", title: "work - Google Chrome")
        h.engine.run("workspace w; project work")
        h.ws.focused = WindowID(1)
        h.engine.run("float")
        let moved = Rect(x: 300, y: 200, width: 500, height: 400)
        h.ws.setFrame(WindowID(1), moved)  // the user drags it
        h.engine.refresh()
        h.engine.run("project pet; project work")
        #expect(h.ws.frame(1) == moved)
    }

    @Test func stateSurvivesRestart() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "Personal")
        h.engine.run("workspace w; project work")
        h.ws.focused = WindowID(1)
        h.engine.run("link pet")

        let h2 = Harness(ws: h.ws, state: h.store.state)
        h2.engine.refresh()
        #expect(h2.engine.activeProject == "work")
        #expect(h2.record(1)?.owner == "pet")
        #expect(!h2.visible(1))
    }

    @Test func restoreAllPutsParkedWindowsBackOnScreen() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "work - Google Chrome")
        h.engine.run("project pet")
        #expect(!Planner(displays: h.ws.displayList, gap: 0).isOnScreen(h.ws.frame(1)))
        h.engine.restoreAll()
        #expect(h.ws.frame(1) == Display.left.visibleFrame)
    }

    @Test func projectsRemovedFromConfigReleaseTheirWindows() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "work - Google Chrome")
        h.engine.run("project work")
        var c = Config.sample
        c.projects.removeAll { $0.name == "work" }
        let h2 = Harness(config: c, ws: h.ws, state: h.store.state)
        h2.engine.refresh()
        #expect(h2.engine.activeProject == nil)
        #expect(h2.record(1)?.owner == nil)
    }

    @Test func focusedOutsiderIsAWindowOutsideTheActiveProject() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "work - Google Chrome")
        h.ws.open(2, bundle: "com.google.Chrome", title: "Personal")
        h.ws.open(3, bundle: "com.apple.finder")
        h.engine.run("workspace w; project work")
        #expect(h.engine.focusedOutsider == nil)  // nothing focused
        h.ws.focused = WindowID(1)
        #expect(h.engine.focusedOutsider == nil)  // in the project
        h.ws.focused = WindowID(2)
        #expect(h.engine.focusedOutsider?.owner == .some(nil))  // unlinked
        h.engine.run("project --none")
        #expect(h.engine.focusedOutsider == nil)  // no project, unlinked window: nothing to point out
        h.ws.focused = WindowID(1)
        #expect(h.engine.focusedOutsider?.owner == "work")  // another project's, before Foci follows it
    }

    @Test func unlinkWithFollowSwitchesToNoProject() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "work - Google Chrome")
        h.ws.open(2, bundle: "com.google.Chrome", title: "work - Google Chrome")
        h.engine.run("workspace w; project work")
        h.ws.focused = WindowID(1)
        h.engine.refresh()

        h.engine.run("unlink --follow")
        #expect(h.record(1)?.owner == nil)
        #expect(h.engine.activeProject == nil)
        #expect(h.visible(1))
        #expect(!h.visible(2))
        #expect(h.ws.focused == WindowID(1))
    }

    @Test func backAndForthToARemovedProjectFails() {
        let h = Harness()
        h.engine.run("project work; project pet")
        var c = Config.sample
        c.projects.removeAll { $0.name == "work" }
        let h2 = Harness(config: c, ws: h.ws, state: h.store.state)
        #expect(h2.engine.run("project-back-and-forth") == ["unknown project 'work'"])
        #expect(h2.engine.activeProject == "pet")
    }
}

@MainActor
struct FrozenWindowTests {
    @Test func minimizedWindowsKeepTheirLinkAndAreNotMoved() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "Personal")
        h.engine.run("workspace w; project work")
        h.ws.focused = WindowID(1)
        h.engine.run("link work")
        h.ws.windowList[0].isFrozen = true
        let frame = h.ws.frame(1)
        h.engine.run("project pet")
        #expect(h.record(1)?.owner == "work")
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
        h.ws.open(1, bundle: "com.google.Chrome", title: "work - Google Chrome")
        h.engine.run("project pet")
        let h2 = Harness(ws: h.ws, state: h.store.state)
        h.ws.focused = nil  // Foci is frontmost right after launch
        h2.engine.refresh()
        h.ws.focused = WindowID(1)  // focus goes back to the previous app
        h2.engine.refresh()
        #expect(h2.engine.activeProject == "pet")
    }
}

@MainActor
struct TilingTests {
    /// Three work Chrome windows on w, tiled.
    func tiled(gap: Double = 0) -> Harness {
        var c = Config.sample
        c.gap = gap
        let h = Harness(config: c)
        for i: UInt32 in 1...3 { h.ws.open(i, bundle: "com.google.Chrome", title: "work - Google Chrome") }
        h.engine.run("workspace w; project work; layout tiles")
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
        h.ws.open(9, bundle: "com.google.Chrome", title: "pet - Google Chrome")
        h.ws.open(10, bundle: "com.google.Chrome", title: "pet - Google Chrome")
        h.engine.run("project pet")
        #expect(h.engine.layout(of: "w").kind == .maximized)
        #expect(h.ws.frame(9) == Display.left.visibleFrame)
        h.engine.run("project work")
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
        let json = #"{"activeProject":"work","windows":{"7":{"workspace":"w","owner":"work","seq":3}}}"#
        let s = try JSONDecoder().decode(State.self, from: Data(json.utf8))
        #expect(s.activeProject == "work")
        #expect(s.windows[WindowID(7)]?.weight == 1)
        #expect(s.layouts == [:])
    }
}

@MainActor
struct TargetWindowTests {
    @Test func commandsActOnAnExplicitWindowEvenWhenHidden() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "work - Google Chrome")
        h.ws.open(2, bundle: "com.google.Chrome", title: "Personal")
        h.engine.run("workspace w; project work")
        h.ws.focused = WindowID(1)
        h.engine.run("project pet")  // window 1 is hidden now, window 2 still shown

        h.engine.run("move-to-workspace c", window: WindowID(1))
        #expect(h.record(1)?.workspace == "c")
        h.engine.run("unlink", window: WindowID(2))
        #expect(h.record(2)?.manual == true)

        h.engine.run("reveal", window: WindowID(1))
        #expect(h.engine.activeProject == "work")
        #expect(h.engine.focusedWorkspace == "c")
        #expect(h.ws.focused == WindowID(1))
    }

    @Test func revealOfAnUnknownWindowFails() {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "work - Google Chrome")
        h.engine.run("project work")
        h.ws.focused = WindowID(1)
        #expect(h.engine.run("reveal", window: WindowID(99)) == ["no window"])
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
        func press(_ key: String) { h.engine.press(KeyCombo(parsing: key)!) }

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

    @Test func repeatKeysKeepTheModeWithOnlyThemselves() {
        var config = Config.sample
        config.modes["control"] = ["j": "focus next", "k": "focus prev", "w": "workspace w", "m": "mode move"]
            .reduce(into: [:]) { $0[KeyCombo(parsing: $1.key)!] = $1.value }
        config.modes["move"] = [KeyCombo(parsing: "w")!: "move-to-workspace w"]
        config.repeatKeys["control"] = [KeyCombo(parsing: "j")!, KeyCombo(parsing: "k")!]
        let h = Harness(config: config)
        h.engine.refresh()
        func press(_ key: String) { h.engine.press(KeyCombo(parsing: key)!) }
        func keys() -> Set<String> { Set(h.engine.bindings.keys.map(\.description)) }

        h.engine.run("mode control")
        #expect(!h.engine.isRepeating)
        press("j")
        #expect(h.engine.mode == "control")
        #expect(h.engine.isRepeating)
        // Other keys reach the app; esc still closes.
        #expect(keys() == ["j", "k", "esc"])
        press("k")
        #expect(h.engine.isRepeating)
        press("w")
        #expect(h.engine.mode == "control")
        press("esc")
        #expect(h.engine.mode == "main")
        #expect(!h.engine.isRepeating)

        // A non-repeat key closes as usual; a new leader starts without repeating.
        h.engine.run("mode control")
        #expect(keys().contains("w"))
        press("w")
        #expect(h.engine.mode == "main")
        h.engine.run("mode control")
        press("m")
        #expect(h.engine.mode == "move")
        #expect(!h.engine.isRepeating)
    }

    @Test func displaysComeAndGoAndWorkspacesFollow() {
        let laptopAlone = Display(
            id: Display.right.id, name: "Color LCD", frame: Rect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: Rect(x: 0, y: 25, width: 1512, height: 957), isMain: true)
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "Personal")
        h.ws.open(2, bundle: "net.kovidgoyal.kitty", args: "kitty")
        h.engine.run("workspace x; workspace w")
        #expect(h.engine.state.activeWorkspace == [Display.left.id: "w", Display.right.id: "x"])
        #expect(h.engine.focusedWorkspace == "w")

        // Unplug the external display: the focused workspace moves to the laptop with its windows.
        h.ws.displayList = [laptopAlone]
        h.engine.refresh()
        #expect(h.engine.state.activeWorkspace == [laptopAlone.id: "w"])
        #expect(h.engine.focusedWorkspace == "w")
        #expect(h.visible(1))
        #expect(h.ws.frame(1) == laptopAlone.visibleFrame)
        #expect(!h.visible(2))

        // Plug it back in: each display shows what it showed before.
        h.ws.displayList = [.left, .right]
        h.engine.refresh()
        #expect(h.engine.state.activeWorkspace == [Display.left.id: "w", Display.right.id: "x"])
        #expect(h.engine.focusedWorkspace == "w")
        #expect(h.ws.frame(1) == Display.left.visibleFrame)
        #expect(h.visible(2))
        #expect(h.ws.frame(2) == Display.right.visibleFrame)
    }
}

@MainActor
struct AccordionTests {
    func harness(padding: Double = 30) -> Harness {
        var c = Config.sample
        c.accordionPadding = padding
        let h = Harness(config: c)
        for id in UInt32(1)...3 { h.ws.open(id, bundle: "com.google.Chrome", title: "work - Google Chrome") }
        h.engine.run("workspace w; project work")
        return h
    }

    @Test func windowsBehindTheFocusedOneShowAtItsSides() {
        let h = harness()
        let a = Display.left.visibleFrame
        h.ws.focused = WindowID(2)
        h.engine.refresh()
        #expect(h.ws.frame(1) == Rect(x: a.x, y: a.y, width: a.width - 30, height: a.height))
        #expect(h.ws.frame(2) == Rect(x: a.x + 30, y: a.y, width: a.width - 60, height: a.height))
        #expect(h.ws.frame(3) == Rect(x: a.x + 30, y: a.y, width: a.width - 30, height: a.height))

        // The first window has nothing before it: no strip on the left.
        h.engine.run("focus prev")
        #expect(h.ws.focused == WindowID(1))
        #expect(h.ws.frame(1) == Rect(x: a.x, y: a.y, width: a.width - 30, height: a.height))
        #expect(h.ws.frame(2) == Rect(x: a.x + 30, y: a.y, width: a.width - 30, height: a.height))
    }

    @Test func oneWindowAndZeroPaddingFillTheDisplay() {
        let h = harness(padding: 0)
        #expect(h.ws.frame(2) == Display.left.visibleFrame)
        let one = Harness(config: { var c = Config.sample; c.accordionPadding = 30; return c }())
        one.ws.open(1, bundle: "com.google.Chrome", title: "work - Google Chrome")
        one.engine.run("workspace w; project work")
        #expect(one.ws.frame(1) == Display.left.visibleFrame)
    }

    @Test func portraitDisplaysKeepTheAccordionLeftToRight() {
        let tall = Display(
            id: DisplayID(1), name: "Portrait", frame: Rect(x: 0, y: 0, width: 1080, height: 1920),
            visibleFrame: Rect(x: 0, y: 25, width: 1080, height: 1895), isMain: true)
        var c = Config.sample
        c.accordionPadding = 30
        let h = Harness(config: c, ws: FakeWindowSystem(displays: [tall]))
        for id in UInt32(1)...2 { h.ws.open(id, bundle: "com.google.Chrome", title: "work - Google Chrome") }
        h.engine.run("workspace w; project work")
        h.ws.focused = WindowID(1)
        h.engine.refresh()
        #expect(h.ws.frame(1) == Rect(x: 0, y: 25, width: 1050, height: 1895))
        #expect(h.ws.frame(2) == Rect(x: 30, y: 25, width: 1050, height: 1895))
    }
}

/// Three monitors of one height in a row, the main one in the middle; the same model left and right.
@MainActor
struct ThreeDisplayTests {
    static let left = Display(
        id: DisplayID(11), name: "DELL U2723QE", frame: Rect(x: -2560, y: 0, width: 2560, height: 1440),
        visibleFrame: Rect(x: -2560, y: 0, width: 2560, height: 1440), isMain: false)
    static let middle = Display(
        id: DisplayID(12), name: "LG HDR 4K", frame: Rect(x: 0, y: 0, width: 2560, height: 1440),
        visibleFrame: Rect(x: 0, y: 25, width: 2560, height: 1415), isMain: true)
    static let right = Display(
        id: DisplayID(13), name: "DELL U2723QE", frame: Rect(x: 2560, y: 0, width: 2560, height: 1440),
        visibleFrame: Rect(x: 2560, y: 0, width: 2560, height: 1440), isMain: false)

    func harness() -> Harness {
        var c = Config.sample
        c.workspaces = ["w": .main, "c": .main, "x": .secondary, "s": .index(3)]
        // Not in display order: the order comes from the frames.
        return Harness(config: c, ws: FakeWindowSystem(displays: [Self.middle, Self.right, Self.left]))
    }

    @Test func displaysAreNumberedFromTheLeft() {
        let h = harness()
        h.engine.refresh()
        #expect(h.engine.orderedDisplays.map(\.id) == [Self.left.id, Self.middle.id, Self.right.id])
        #expect(h.engine.display(of: "x").id == Self.left.id)  // secondary: the first other one from the left
        #expect(h.engine.display(of: "s").id == Self.right.id)
        #expect(h.engine.state.activeWorkspace == [Self.left.id: "x", Self.middle.id: "c", Self.right.id: "s"])
        #expect(CLIHandler(engine: h.engine).status().displays.map(\.workspace) == ["x", "c", "s"])
    }

    @Test func focusDisplayByNumberSideAndCycle() {
        let h = harness()
        h.engine.refresh()
        h.engine.run("focus-display 3")
        #expect(h.engine.focusedWorkspace == "s")
        h.engine.run("focus-display left")
        #expect(h.engine.focusedWorkspace == "c")
        h.engine.run("focus-display left")
        #expect(h.engine.focusedWorkspace == "x")
        // Nothing further left; next|prev wrap around.
        h.engine.run("focus-display left")
        #expect(h.engine.focusedWorkspace == "x")
        h.engine.run("focus-display prev")
        #expect(h.engine.focusedWorkspace == "s")
        h.engine.run("focus-display main")
        #expect(h.engine.focusedWorkspace == "c")
        h.engine.run("focus-display 4")
        #expect(h.engine.focusedWorkspace == "c")
    }

    @Test func moveWindowAndWorkspaceToADisplayByNumber() {
        let h = harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "Personal")
        h.engine.run("workspace w")
        h.ws.focused = WindowID(1)
        h.engine.run("move-to-display 3")
        #expect(h.record(1)?.workspace == "s")
        #expect(h.ws.frame(1) == Self.right.visibleFrame)
        #expect(h.engine.focusedWorkspace == "w")
        h.ws.focused = WindowID(1)
        h.engine.run("move-to-display --follow 1")
        #expect(h.record(1)?.workspace == "x")
        #expect(h.engine.focusedWorkspace == "x")
        #expect(h.ws.frame(1) == Self.left.visibleFrame)

        h.engine.run("workspace w; move-workspace-to-display 3")
        #expect(h.engine.display(of: "w").id == Self.right.id)
        #expect(h.engine.state.activeWorkspace[Self.right.id] == "w")
        #expect(h.engine.state.activeWorkspace[Self.middle.id] == "c")
        #expect(h.engine.focusedWorkspace == "w")
    }

    @Test func displayOrderFromTheConfig() {
        var c = Config.sample
        c.displayOrder = ["main", "dell", "nothing like it", "dell"]
        c.workspaces = ["w": .main, "x": .secondary, "s": .index(3)]
        let h = Harness(config: c, ws: FakeWindowSystem(displays: [Self.middle, Self.right, Self.left]))
        h.engine.refresh()
        // Main first, then the two monitors of one model left to right; an entry matching nothing is skipped.
        #expect(h.engine.orderedDisplays.map(\.id) == [Self.middle.id, Self.left.id, Self.right.id])
        #expect(h.engine.display(of: "x").id == Self.left.id)
        #expect(h.engine.display(of: "s").id == Self.right.id)
        h.engine.run("focus-display 3")
        #expect(h.engine.focusedWorkspace == "s")
        h.engine.run("focus-display next")
        #expect(h.engine.display(of: h.engine.focusedWorkspace).id == Self.middle.id)
        // Sides still follow the arrangement, not the numbers.
        h.engine.run("focus-display left")
        #expect(h.engine.display(of: h.engine.focusedWorkspace).id == Self.left.id)
        #expect(CLIHandler(engine: h.engine).status().displays.map(\.id) == [12, 11, 13])

        // Partly listed: the rest follow left to right.
        #expect(Display.ordered([Self.left, Self.middle, Self.right], by: ["right"]).map(\.id.raw) == [11, 12, 13])
        #expect(Display.ordered([Self.left, Self.middle, Self.right], by: ["lg"]).map(\.id.raw) == [12, 11, 13])
    }

    @Test func externalDisplaysAreNamedExtFromTheLeft() {
        let laptop = Display(
            id: DisplayID(14), name: "Built-in Retina Display", frame: Rect(x: 5120, y: 0, width: 1512, height: 982),
            visibleFrame: Rect(x: 5120, y: 0, width: 1512, height: 982), isMain: false, isBuiltIn: true)
        var c = Config.sample
        // Names, not numbers: 'ext 2' is the second monitor from the left whatever the order.
        c.displayOrder = ["built-in", "ext2"]
        c.workspaces = ["w": .main, "x": .name("ext 1"), "s": .name("Built-In")]
        let h = Harness(config: c, ws: FakeWindowSystem(displays: [Self.middle, laptop, Self.right, Self.left]))
        h.engine.refresh()
        #expect(h.engine.orderedDisplays.map { h.engine.label(of: $0) } == ["built-in", "ext 2", "ext 1", "ext 3"])
        #expect(h.engine.display(of: "x").id == Self.left.id)
        #expect(h.engine.display(of: "s").id == laptop.id)
        h.engine.run("focus-display ext 3")
        #expect(h.engine.display(of: h.engine.focusedWorkspace).id == Self.right.id)
        h.engine.run("focus-display ext-1")
        #expect(h.engine.display(of: h.engine.focusedWorkspace).id == Self.left.id)
        let status = CLIHandler(engine: h.engine).status().displays
        #expect(status.map(\.name) == ["built-in", "ext 2", "ext 1", "ext 3"])
        #expect(status.map(\.model) == ["Built-in Retina Display", "LG HDR 4K", "DELL U2723QE", "DELL U2723QE"])
        // The model name still works; 'ext 1' doesn't match 'ext 10'-like prefixes, only the whole name.
        #expect(DisplaySpec.name("lg").resolve(in: h.engine.displays)?.id == Self.middle.id)
        #expect(DisplaySpec.name("ext").resolve(in: h.engine.displays) == nil)
        // No laptop screen (clamshell): only ext.
        #expect(Display.labels([Self.left, Self.middle]) == [Self.left.id: "ext 1", Self.middle.id: "ext 2"])
    }

    @Test func theMiddleDisplayParksInAFreeOuterCorner() {
        let h = harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "work - Google Chrome")
        h.engine.run("workspace w; project pet")
        // Both corners of the middle display touch a neighbour: the left display's outer corner.
        #expect(h.ws.frame(1) == Rect(x: -2560 - 800 + 1, y: 1439, width: 800, height: 600))
        let others = [Self.middle, Self.right].map(\.frame)
        #expect(others.allSatisfy { h.ws.frame(1).overlapArea($0) == 0 })
    }

    @Test func parkingPrefersTheOwnDisplaysFreeCorner() {
        let laptop = Display(
            id: DisplayID(14), name: "Color LCD", frame: Rect(x: 2560, y: 0, width: 1512, height: 982),
            visibleFrame: Rect(x: 2560, y: 0, width: 1512, height: 982), isMain: false)
        let p = Planner(displays: [Self.left, Self.middle, laptop], gap: 0)
        let size = Rect(x: 0, y: 0, width: 800, height: 600)
        // The laptop is shorter: the middle display's bottom-right corner is free.
        #expect(p.parkedFrame(size: size, on: Self.middle) == Rect(x: 2559, y: 1439, width: 800, height: 600))
        #expect(p.parkedFrame(size: size, on: laptop) == Rect(x: 2560 + 1512 - 1, y: 981, width: 800, height: 600))
        #expect(p.parkedFrame(size: size, on: Self.left) == Rect(x: -2560 - 799, y: 1439, width: 800, height: 600))
    }

    @Test func sidesFollowTheArrangement() {
        // A laptop under the main display, a monitor to its right.
        let laptop = Display(
            id: DisplayID(14), name: "Color LCD", frame: Rect(x: 500, y: 1440, width: 1512, height: 982),
            visibleFrame: Rect(x: 500, y: 1440, width: 1512, height: 982), isMain: false)
        let all = [Self.middle, Self.right, laptop]
        #expect(Self.middle.neighbour(.down, in: all)?.id == laptop.id)
        #expect(laptop.neighbour(.up, in: all)?.id == Self.middle.id)
        #expect(Self.middle.neighbour(.right, in: all)?.id == Self.right.id)
        #expect(laptop.neighbour(.right, in: all)?.id == Self.right.id)
        #expect(Self.middle.neighbour(.left, in: all) == nil)
        #expect(Display.ordered(all).map(\.id) == [Self.middle.id, laptop.id, Self.right.id])
    }
}

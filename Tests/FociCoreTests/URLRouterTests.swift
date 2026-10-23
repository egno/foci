import Foundation
import Testing

@testable import FociCore

@MainActor
struct URLRouterTests {
    static var config: Config {
        var c = Config.sample
        c.apps["chrome"]!.openURL = "open -a 'Google Chrome' {url}"
        c.apps["chrome"]!.globalOpenURL = "open -a 'Google Chrome' {url}"
        c.browser = "chrome"
        return c
    }

    /// Chrome (pid 10) has a window per project and a personal one; kitty runs per project; Slack is unlinked.
    func harness(config: Config = Self.config) -> Harness {
        let h = Harness(config: config)
        h.ws.open(1, bundle: "com.google.Chrome", title: "bil - Google Chrome", pid: 10)
        h.ws.open(2, bundle: "com.google.Chrome", title: "iam - Google Chrome", pid: 10)
        h.ws.open(3, bundle: "com.google.Chrome", title: "Personal", pid: 10)
        h.ws.open(4, bundle: "net.kovidgoyal.kitty", args: "kitty --instance-group bil", pid: 20)
        h.ws.open(5, bundle: "net.kovidgoyal.kitty", args: "kitty --instance-group iam", pid: 21)
        h.ws.open(6, bundle: "com.tinyspeck.slackmacgap", pid: 30)
        h.engine.run("project bil; workspace s")
        return h
    }

    @Test func linkFromUnlinkedWindowOpensInActiveProjectsBrowser() {
        let h = harness()
        h.ws.focused = WindowID(6)
        #expect(h.engine.openURL("https://x.io/a?b=c", opener: [30]) == [])
        #expect(h.engine.focusedWorkspace == "w")
        #expect(h.ws.focused == WindowID(1))
        #expect(h.launcher.commands.last?.0 == "open -a 'Google Chrome' 'https://x.io/a?b=c'")
        #expect(h.launcher.commands.last?.1 == ["FOCI_PROJECT": "bil"])
    }

    @Test func linkFromHiddenProjectsTerminalSwitchesToThatProject() {
        let h = harness()
        h.ws.focused = WindowID(6)
        // `open` (pid 99) started by zsh (98) in iam's kitty.
        h.engine.openURL("https://x.io", opener: [99, 98, 21])
        #expect(h.engine.activeProject == "iam")
        #expect(h.ws.focused == WindowID(2))
        #expect(h.visible(2) && !h.visible(1))
    }

    @Test func openerWithWindowsOfSeveralProjectsMeansActiveProject() {
        let h = harness()
        h.ws.focused = WindowID(6)
        h.engine.openURL("https://x.io", opener: [10])  // Chrome itself, not focused
        #expect(h.engine.activeProject == "bil")
        #expect(h.ws.focused == WindowID(1))
    }

    @Test func prefersTheLastFocusedBrowserWindow() {
        let h = harness()
        h.ws.open(7, bundle: "com.google.Chrome", title: "bil - Google Chrome", pid: 10)
        h.engine.run("workspace w")
        h.ws.focused = WindowID(1)
        h.engine.refresh()
        h.engine.run("workspace s")
        h.engine.openURL("https://x.io")
        #expect(h.ws.focused == WindowID(1))
    }

    @Test func projectWithoutBrowserWindowLaunchesWithTheLink() {
        var c = Self.config
        c.projects.append(ProjectDef(name: "gc", apps: [ProjectAppRef(app: "chrome", autostart: false)]))
        let h = harness(config: c)
        h.engine.run("project gc; workspace s")
        h.engine.openURL("https://x.io")
        #expect(h.launcher.commands.last?.0 == "open -na 'Google Chrome' --args --new-window 'https://x.io'")
        #expect(h.engine.focusedWorkspace == "w")

        h.engine.openURL("https://y.io")  // while Chrome is still starting: not dropped
        #expect(h.launcher.commands.last?.0 == "open -na 'Google Chrome' --args --new-window 'https://y.io'")

        h.ws.open(8, bundle: "com.google.Chrome", title: "y.io - Google Chrome", pid: 10)
        h.engine.refresh()
        #expect(h.record(8)?.owner == "gc")
    }

    @Test func withoutProjectTheBrowserOpensTheLinkInAnUnlinkedWindow() {
        let h = harness()
        h.engine.run("project --none")
        h.engine.openURL("https://x.io")
        #expect(h.ws.focused == WindowID(3))
        #expect(h.launcher.commands.last?.0 == "open -a 'Google Chrome' 'https://x.io'")
        #expect(h.launcher.commands.last?.1 == [:])

        h.ws.windowList.removeAll { $0.id == WindowID(3) }
        h.engine.openURL("https://y.io")
        #expect(h.launcher.commands.last?.0 == "open -a 'Google Chrome' 'https://y.io'")  // global-launch
    }

    @Test func projectWithoutBrowserAppFallsBackToTheBrowser() {
        var c = Self.config
        c.projects.append(ProjectDef(name: "ops", apps: [ProjectAppRef(app: "kitty", autostart: false)]))
        let h = harness(config: c)
        h.engine.run("project ops")
        h.engine.openURL("https://x.io")
        #expect(h.engine.activeProject == "ops")
        #expect(h.ws.focused == WindowID(3))
    }

    @Test func noBrowserIsAnError() {
        var c = Config.sample
        c.browser = nil
        let h = harness(config: c)
        h.engine.run("project --none")
        let before = h.launcher.commands.count
        #expect(h.engine.openURL("https://x.io").count == 1)
        #expect(h.launcher.commands.count == before)
    }

    @Test func linkIsShellQuoted() {
        #expect(
            Engine.substitute("open -a X {url}", url: "https://x.io/?q='; rm -rf ~", project: nil)
                == #"open -a X 'https://x.io/?q='\''; rm -rf ~'"#)
    }
}

import Foundation
import Testing

@testable import FociCore

struct CLIParseTests {
    @Test func bareCommandsBecomeScripts() throws {
        #expect(try CLIRequest.parse(["project", "bil"]) == .run(script: "project bil", window: nil))
        #expect(try CLIRequest.parse(["workspace w; layout tiles"]) == .run(script: "workspace w; layout tiles", window: nil))
        #expect(try CLIRequest.parse(["run", "--window", "42", "unlink"]) == .run(script: "unlink", window: WindowID(42)))
        #expect(try CLIRequest.parse([]) == .help)
    }

    @Test func listWindowsFilters() throws {
        var f = CLIRequest.WindowFilter()
        f.owner = .project("bil")
        f.workspace = "w"
        f.visibleOnly = true
        #expect(
            try CLIRequest.parse(["list-windows", "--project", "bil", "--workspace", "w", "--visible", "--json"])
                == .listWindows(f, json: true))
    }

    @Test func usageErrors() {
        #expect(throws: CLIRequest.UsageError.self) { try CLIRequest.parse(["teleport"]) }
        #expect(throws: CLIRequest.UsageError.self) { try CLIRequest.parse(["list-windows", "--project"]) }
        #expect(throws: CLIRequest.UsageError.self) { try CLIRequest.parse(["status", "extra"]) }
        #expect(throws: CLIRequest.UsageError.self) { try CLIRequest.parse(["run", "--window", "x", "unlink"]) }
    }
}

@MainActor
struct CLIHandlerTests {
    func harness() -> Harness {
        let h = Harness()
        h.ws.open(1, bundle: "com.google.Chrome", title: "bil - Google Chrome", pid: 10)
        h.ws.open(2, bundle: "com.google.Chrome", title: "Personal", pid: 10)
        h.ws.open(3, bundle: "net.kovidgoyal.kitty", args: "kitty --instance-group iam", pid: 20)
        h.engine.run("workspace w; project bil")
        return h
    }

    @Test func runReportsErrorsWithExitCode() {
        let h = harness()
        let cli = CLIHandler(engine: h.engine)
        #expect(cli.handle(.run(script: "project iam", window: nil)) == CLIResponse())
        #expect(h.engine.activeProject == "iam")
        let bad = cli.handle(.run(script: "project nope", window: nil))
        #expect(bad.exitCode == 1)
        #expect(bad.stderr == "unknown project 'nope'\n")
    }

    @Test func windowFilters() {
        let h = harness()
        let cli = CLIHandler(engine: h.engine)
        func ids(_ f: (inout CLIRequest.WindowFilter) -> Void) -> [UInt32] {
            var filter = CLIRequest.WindowFilter()
            f(&filter)
            return cli.windows(filter).map(\.id)
        }
        #expect(ids { _ in } == [1, 2, 3])
        #expect(ids { $0.owner = .active } == [1])
        #expect(ids { $0.owner = .unlinked } == [2])
        #expect(ids { $0.owner = .project("iam") } == [3])
        #expect(ids { $0.visibleOnly = true } == [1, 2])
        #expect(ids { $0.pid = 20 } == [3])
    }

    @Test func statusAndJSON() throws {
        let h = harness()
        let s = CLIHandler(engine: h.engine).status()
        #expect(s.project == "bil")
        #expect(s.focusedWorkspace == "w")
        #expect(s.displays.map(\.workspace) == ["w", "s"])

        let out = CLIHandler(engine: h.engine).handle(.listProjects(json: true)).stdout
        let projects = try JSONDecoder().decode([ProjectDTO].self, from: Data(out.utf8))
        #expect(projects == [ProjectDTO(name: "bil", active: true, windows: 1), ProjectDTO(name: "iam", active: false, windows: 1)])
    }

    @Test func workspacesCountWindowsOfTheActiveProject() {
        let h = harness()
        let list = CLIHandler(engine: h.engine).workspaces()
        let w = list.first { $0.name == "w" }
        #expect(w == WorkspaceDTO(name: "w", display: "LG HDR 4K", shown: true, focused: true, layout: "maximized", windows: 2))
        #expect(list.first { $0.name == "x" }?.windows == 0)  // iam's kitty
    }

    @Test func tableAlignsColumns() {
        let r = CLIHandler.table(["A", "B"], [["long", "x"], ["s", "y"]])
        #expect(r.stdout == "A     B\nlong  x\ns     y\n")
    }
}

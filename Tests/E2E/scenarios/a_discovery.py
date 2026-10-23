"""A. Discovery and linking by rules (Tests/E2E/SCENARIOS.md).

The reference for the other groups: one `test_<ID>(h)` per spec scenario, the docstring names it, marks from
`harness` say what the scenario needs, and the body drives Foci through `h` and checks the outcome.
"""
from harness import (FIXTURE_EXPECT, FIXTURE_WINDOWS, Rect, fixture, fresh_state, needs_displays, questionable)


def window_ids(h):
    return {w["id"] for w in h.windows()}


@fresh_state
@needs_displays(2)
def test_A0(h):
    """A0 Fresh state: main shows c, the side display s, no project; back-and-forth is a no-op."""
    st = h.status()
    h.eq(st["project"], None, "project")
    h.eq(h.shown_on(h.main.name), "c", "workspace on main")
    h.eq(h.shown_on(h.side.name), "s", "workspace on the side display")
    h.eq(st["focusedWorkspace"], "c", "focused workspace")
    before_state = h.state()
    r = h.cmd("project-back-and-forth")
    h.eq(r.err, "", "stderr")
    h.eq(h.status(), st, "status after project-back-and-forth")
    h.eq(h.state(), before_state, "state.json after project-back-and-forth")


@fixture()
@needs_displays(2)
def test_A1(h):
    """A1 Rules link new windows and place them on the app's workspace."""
    names = ["aw", "bw", "at", "bt", "ch"]
    h.start_fixture_windows(names)
    h.settle()
    h.check_fixture(names)  # owners and workspaces as in the fixture table
    h.eq(h.project(), "alpha", "project")
    for n in ("aw", "at"):
        h.shown(n)
    for n in ("bw", "bt", "ch"):  # beta's windows, and `s` is not shown
        h.parked(n)
    h.maximized("aw")
    h.maximized("at")


@fixture()
def test_A2(h):
    """A2 An unmatched window is unlinked, on the focused workspace."""
    h.eq(h.focused_workspace(), "w", "focused workspace")
    h.start_textedit()
    h.wait_window("te.txt")
    h.settle()
    r = h.rec("te")
    h.eq((r["project"], r["workspace"], r["visible"]), (None, "w", True), "TextEdit (project, workspace, visible)")
    h.shown("te")
    for script in ("project beta", "project --none"):
        h.cmd(script)
        h.eq(h.rec("te")["visible"], True, "TextEdit visible after %r" % script)
        h.shown("te")


@fixture("aw")
def test_A3(h):
    """A3 manage = false windows are ignored."""
    p = h.launch_probe("b", "ig", ["--group", "ignored"], title="ignored win")
    h.settle_os()
    h.check(p.pid not in {w["pid"] for w in h.windows()}, "the ignored window is in list-windows")
    vis = h.main.visible
    p.move("ignored win", vis.x + 300, vis.y + 200, 500, 400)
    h.settle_os()
    before = p.frame("ignored win")
    h.check(before.close_to(Rect(vis.x + 300, vis.y + 200, 500, 400)), "the drag did not take: %s" % (before,))
    for script in ("project beta", "workspace c", "workspace w", "project alpha", "project --none", "project alpha"):
        h.cmd(script)
        h.eq(p.frame("ignored win").close_to(before), True,
             "ignored window moved after %r: %s -> %s" % (script, before, p.frame("ignored win")))
    h.settle_os()
    h.check(p.frame("ignored win").close_to(before), "ignored window moved after a refresh")
    h.check(p.pid not in {w["pid"] for w in h.windows()}, "the ignored window is in list-windows")


@fixture("aw", "aw2")
def test_A4(h):
    """A4 floating = true app: kept at its frame, not a tile."""
    vis = h.main.visible
    p = h.launch_probe("b", "dg", ["--group", "dialog"], title="dialog", size="400x300")
    h.wait_window("dialog", "dg")
    x, y = vis.x + (vis.w - 400) / 2, vis.y + (vis.h - 300) / 2
    p.move("dialog", x, y, 400, 300)
    h.settle_os()
    h.register("dg", "dg", "dialog")
    r = h.rec("dg")
    h.eq((r["floating"], r["project"], r["workspace"]), (True, None, "w"), "dialog (floating, project, workspace)")
    before = h.frame("dg")
    h.check(before.close_to(Rect(x, y, 400, 300)), "dialog is at %s, expected the middle of main" % (before,))
    h.cmd("layout tiles")
    h.settle_os()
    half = vis.w / 2
    for n in ("aw", "aw2"):  # two tiles, not three: the dialog does not count
        f = h.frame(n)
        h.check(abs(f.w - half) <= 1 and abs(f.h - vis.h) <= 1, "%s is %s, expected a half of %s" % (n, f, vis))
    h.frame_unchanged("dg", before)


@fixture("aw")
def test_A5(h):
    """A5 new-windows = 'active-project': a new window joins the active project if it uses the app."""
    pc = h.launch_probe("c", "pc", title="untitled")
    h.wait_window("untitled", "pc")
    h.register("n1", "pc", "untitled")
    h.eq(h.rec("n1")["project"], "alpha", "first notes window, alpha active")
    h.cmd("project --none")
    pc.new_window("second")
    h.wait_window("second", "pc")
    h.register("n2", "pc", "second")
    h.eq(h.rec("n2")["project"], None, "second notes window, no project")
    h.cmd("project beta")  # beta doesn't use notes
    pc.new_window("third")
    h.wait_window("third", "pc")
    h.register("n3", "pc", "third")
    h.eq(h.rec("n3")["project"], None, "third notes window, beta active")
    pc.new_window("alpha notes")  # the title rule links it to alpha, whatever is active
    h.wait_window("alpha notes", "pc")
    h.register("n4", "pc", "alpha notes")
    h.eq(h.rec("n4")["project"], "alpha", "'alpha notes' by the title rule")
    h.settle()
    h.parked("n4")  # beta is active
    h.eq(h.rec("n1")["project"], "alpha", "first notes window keeps its owner")


@fixture("aw")
def test_A6(h):
    """A6 A renamed window gets linked by a title rule."""
    pa = h.probes["pa"]
    pa.new_window("scratch")
    h.wait_window("scratch", "pa")
    h.register("sc", "pa", "scratch")
    r = h.rec("sc")
    h.eq((r["project"], r["workspace"], r["visible"]), (None, "w", True), "scratch (project, workspace, visible)")
    pa.rename("scratch", "beta - web")
    h.wins["sc"].title = "beta - web"
    h.wait_until(lambda: h.rec("sc")["project"] == "beta", 6, "the renamed window to be linked to beta")
    h.settle()
    h.parked("sc")  # alpha is active


@fixture("aw")
def test_A7(h):
    """A7 Manual unlink beats title rules."""
    aw = h.wins["aw"]
    wid = aw.id
    r = h.foci("run", "--window", wid, "unlink")
    h.eq(r.code, 0, "unlink exit code")
    h.settle()
    h.eq(h.rec("aw")["project"], None, "aw after unlink")
    h.probes["pa"].rename("alpha - web", "alpha - web 3")  # still matches ^{project} - web
    aw.title = "alpha - web 3"
    h.settle_os()
    h.eq(h.rec("aw")["project"], None, "aw after the rename")
    h.eq(h.state()["windows"][str(wid)]["manual"], True, "manual in state.json")


@needs_displays(2)
def test_A8(h):
    """A8 Closed windows disappear (their ID leaves `windows` in state.json; `lastFocused` may keep it)."""
    bw = h.wins["bw"]
    wid = bw.id
    before = {p["name"]: p["windows"] for p in h.projects()}
    h.eq(before["beta"], 2, "beta's windows before")
    h.check(str(wid) in h.state()["windows"], "bw is not in state.json before the test")
    h.probes["pa"].close_window("beta - web")
    h.wait_gone("beta - web", "pa")
    h.settle()
    h.check(wid not in window_ids(h), "bw is still in list-windows")
    after = {p["name"]: p["windows"] for p in h.projects()}
    h.eq(after["beta"], 1, "beta's windows after")
    h.eq(after["alpha"], before["alpha"], "alpha's windows")
    h.check(str(wid) not in h.state()["windows"], "bw is still in state.json")


@needs_displays(2)
def test_A9(h):
    """A9 App restart re-links by rules: new window IDs, same owners and workspaces, old IDs dropped."""
    h.cmd("layout tiles")  # w in tiles
    group = ["at", "bt", "ae", "ch"]
    old = {n: h.wins[n].id for n in group}
    before = {n: h.frame(n) for n in ("aw", "aw2")}
    for proc in group:
        h.probes[proc].quit()
    for n in group:
        h.wait_until(lambda n=n: old[n] not in window_ids(h), 10, "%s to vanish from list-windows" % n)
    h.settle()
    h.check(not set(map(str, old.values())) & set(h.state()["windows"]), "old IDs are still in state.json")
    h.start_fixture_windows(group)  # the same launch commands
    h.settle()
    for n in group:
        h.check(h.wins[n].id not in old.values(), "%s got an old window ID back" % n)
        h.eq((h.rec(n)["project"], h.rec(n)["workspace"]), FIXTURE_EXPECT[n], "%s (owner, workspace)" % n)
    h.check(not set(map(str, old.values())) & set(h.state()["windows"]), "old IDs are back in state.json")
    h.shown("at")
    for n in ("bt", "ae", "ch"):
        h.parked(n)
    for n, f in before.items():
        h.frame_unchanged(n, f)


@fixture("aw")
@questionable("an unmatched Probe B window falls back to the first per-project def by id (editor): linked to no "
              "project, on the def's workspace c")
def test_A10(h):
    """A10 Fallback def: a Probe B window matching no rule is an unlinked `editor` window on c."""
    p = h.launch_probe("b", "ot", ["--group", "other"], title="other")
    h.wait_window("other", "ot")
    h.register("ot", "ot", "other")
    h.settle()
    r = h.rec("ot")
    h.eq((r["project"], r["workspace"], r["visible"]), (None, "c", False), "(project, workspace, visible)")
    h.eq(h.state()["windows"][str(r["id"])]["app"], "editor", "app def in state.json")
    h.parked("ot")  # c is not shown (switching there would autostart alpha's editor)

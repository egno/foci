"""G. Manual linking (Tests/E2E/SCENARIOS.md)."""
from harness import Fail, fixture, osascript


def _focus_te(h):
    """Makes the TextEdit document the system's focused window (the Probe's `focus` command is for probes)."""
    osascript('tell application "TextEdit" to activate')

    def focused():
        pid = h.textedit_pid()
        return pid is not None and h.focused_window() == (pid, "te.txt")
    h.wait_until(focused, 8, "TextEdit's window to be focused")


def _wait_focused(h, name, timeout=6):
    h.wait_focused(name, timeout)


def _manual(h, wid):
    """`manual` of a window in state.json (absent counts as false)."""
    return bool(h.state()["windows"][str(wid)].get("manual", False))


@fixture("aw", "aw2", "te")
def test_G1(h):
    """G1 Link to another project: the window is parked, focus moves to the best window of the workspace."""
    _focus_te(h)
    wid = h.wins["te"].id
    h.eq(h.rec("te")["project"], None, "te before")
    h.cmd("link beta")
    h.eq(h.rec("te")["project"], "beta", "te owner after link beta")
    h.settle()
    h.parked("te")  # alpha is active
    # focusBest(in: w): the last focused alpha window of w (te itself is no candidate any more), else the first
    _wait_focused(h, "aw")
    h.eq(_manual(h, wid), True, "manual in state.json")  # list-windows doesn't show it


@fixture("aw", "aw2", "te")
def test_G2(h):
    """G2 Link to the active project; without an active project it fails with `no active project`."""
    _focus_te(h)
    h.cmd("project --none")
    _focus_te(h)
    h.cmd("link --active", code=1, err="no active project")
    h.eq(h.rec("te")["project"], None, "te after the failed link")
    h.eq(h.project(), None, "project")
    h.cmd("project alpha")
    _focus_te(h)
    wid = h.wins["te"].id
    h.cmd("link --active")
    h.eq(h.rec("te")["project"], "alpha", "te owner after link --active")
    h.shown("te")
    h.eq(_manual(h, wid), True, "manual in state.json")
    h.cmd("project beta")
    h.eq(h.rec("te")["project"], "alpha", "te owner after project beta")
    h.parked("te")


@fixture("aw")
def test_G3(h):
    """G3 Unknown project: exit 1 `unknown project 'nope'`, nothing changes."""
    wid = h.wins["aw"].id
    h.focused("aw")
    h.cmd("link nope", code=1, err="unknown project 'nope'")
    h.eq(h.rec("aw")["project"], "alpha", "aw owner")
    h.eq(_manual(h, wid), False, "manual in state.json")
    h.shown("aw")


@fixture("aw", "bw")
def test_G4(h):
    """G4 Unlink: the window stays shown whatever the project; a rename doesn't re-link it (manual)."""
    wid = h.wins["aw"].id
    h.focused("aw")
    h.cmd("unlink")
    h.eq(h.rec("aw")["project"], None, "aw after unlink")
    h.eq(_manual(h, wid), True, "manual in state.json")
    for script in ("project beta", "project --none"):
        h.cmd(script)
        h.eq(h.rec("aw")["project"], None, "aw owner after %r" % script)
        h.shown("aw")
    h.probes["pa"].rename("alpha - web", "alpha - web 3")  # still matches ^{project} - web
    h.wins["aw"].title = "alpha - web 3"
    h.settle_os()
    h.eq(h.rec("aw")["project"], None, "aw owner after the rename")
    h.shown("aw")


@fixture("aw", "bw")
def test_G5(h):
    """G5 One process, several projects: a switch parks one window and shows the other, the app is not hidden."""
    pa = h.probes["pa"]
    h.eq(h.rec("aw")["pid"], h.rec("bw")["pid"], "aw and bw are windows of one process")
    h.eq((h.rec("aw")["workspace"], h.rec("bw")["workspace"]), ("w", "w"), "workspaces")

    def not_hidden(step):
        st = pa.state()
        h.eq(st["hidden"], False, "Probe A hidden %s" % step)
        h.check(pa.alive(), "Probe A is not running %s" % step)
        for n in ("aw", "bw"):
            h.eq(h.rec(n)["frozen"], False, "%s frozen %s" % (n, step))
        for w in pa.windows():
            h.eq(w["minimized"], False, "%r minimized %s" % (w["title"], step))

    h.shown("aw")
    h.parked("bw")
    not_hidden("with alpha")
    h.cmd("project beta")
    h.shown("bw")
    h.parked("aw")
    not_hidden("with beta")
    h.cmd("project alpha")
    h.shown("aw")
    h.parked("bw")
    not_hidden("with alpha again")


@fixture("aw", "te")
def test_G6(h):
    """G6 Manual links don't survive the app's restart: TextEdit comes back unlinked (no rule matches it)."""
    _focus_te(h)
    old = h.wins["te"].id
    h.cmd("link beta")
    h.eq(h.rec("te")["project"], "beta", "te owner after link beta")
    h.eq(_manual(h, old), True, "manual in state.json")
    osascript('tell application "TextEdit" to quit')
    h.wait_until(lambda: h.textedit_pid() is None, 10, "TextEdit to quit")
    h.settle_os()
    h.check(old not in {w["id"] for w in h.windows()}, "the old TextEdit window is still in list-windows")
    h.start_textedit()  # a new process, a new window ID
    h.wait_window("te.txt", timeout=15)
    h.settle()
    r = h.rec("te")
    h.check(r["id"] != old, "TextEdit's window got its old ID back")
    h.eq((r["project"], r["workspace"], r["visible"]), (None, "w", True), "te (project, workspace, visible)")
    h.eq(h.state()["windows"][str(r["id"])].get("manual", False), False, "manual of the new window")
    h.check(str(old) not in h.state()["windows"], "the old window is still in state.json")
    h.shown("te")

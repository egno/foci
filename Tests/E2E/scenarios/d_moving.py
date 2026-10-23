"""D. Moving windows (Tests/E2E/SCENARIOS.md).

The side display of the test Mac can be below `main`, not to its right: all geometry comes from `h.displays()`,
`h.main` and `h.side`. Neighbour order for `move-to-display` and friends is by `frame.x`, like `Engine.neighbour`.
"""
from harness import Rect, needs_displays, one_display, questionable


# ---------------------------------------------------------------------- private helpers


def other_display(h, d, direction="next"):
    """The display `move-to-display <direction>` reaches from `d`: displays sorted by frame.x, wrapping."""
    ds = sorted(h.displays(), key=lambda x: x.frame.x)
    i = [x.id for x in ds].index(d.id)
    return ds[(i + (1 if direction == "next" else -1)) % len(ds)]


def focused(h, name, timeout=4):
    """focused(W), polled: focus changes are asynchronous."""
    w = h.wins[name]
    try:
        h.wait_until(lambda: h.focused_window() == (w.pid, w.title), timeout, "%s to be focused" % name)
    except AssertionError:
        h.focused(name)  # raises with the details
        raise


def focus_window(h, name):
    """Makes a (visible!) Probe window the system's focused window, like the user clicking it."""
    h.focus_window(name)


def snapshot(h):
    """What a failing command must not change: status, windows, and every probe window's frame."""
    return (h.status(), h.windows(), {n: h.frame(n) for n in h.wins if h.wins[n].proc != "te"})


# ---------------------------------------------------------------------- scenarios


def test_D1(h):
    """D1 move-to-workspace without --follow: the window leaves, the focused workspace stays."""
    h.cmd("move-to-workspace c")
    r = h.rec("aw")
    h.eq((r["workspace"], r["visible"]), ("c", False), "aw (workspace, visible)")
    h.parked("aw")  # c is not shown
    h.eq(h.focused_workspace(), "w", "focused workspace")
    h.eq(h.shown_on(h.main.name), "w", "workspace on main")
    focused(h, "aw2")  # the first remaining window of w


def test_D2(h):
    """D2 move-to-workspace --follow: the workspace is shown and the window focused."""
    h.cmd("move-to-workspace --follow c")
    h.eq(h.rec("aw")["workspace"], "c", "workspace of aw")
    h.eq(h.focused_workspace(), "c", "focused workspace")
    h.eq(h.shown_on(h.main.name), "c", "workspace on main")
    for n in ("aw", "ae"):
        h.shown(n)
        h.maximized(n)
    for n in ("aw2", "te"):
        h.parked(n)
    focused(h, "aw")


def test_D3(h):
    """D3 An ad hoc target workspace is created on the display of the focused workspace, not of the window."""
    h.cmd("move-to-workspace --follow z")
    h.eq(h.display_of("z").id, h.main.id, "display of z")
    h.eq(h.shown_on(h.main.name), "z", "workspace on main")
    h.eq(h.focused_workspace(), "z", "focused workspace")
    h.eq(h.rec("aw")["workspace"], "z", "workspace of aw")
    h.shown("aw")
    h.maximized("aw")
    focused(h, "aw")
    h.eq(h.state()["workspaceDisplay"].get("z"), h.main.id, "workspaceDisplay[z] in state.json")
    h.cmd("workspace w")
    h.eq(h.focused_workspace(), "w", "focused workspace")
    r = h.run_on("at", "move-to-workspace z2")  # `at` lives on x, on the side display
    h.eq(r.code, 0, "run --window exit code")
    h.settle()
    h.eq(h.rec("at")["workspace"], "z2", "workspace of at")
    h.eq(h.display_of("z2").id, h.main.id, "display of z2 (the focused workspace's, not at's)")
    h.eq(h.state()["workspaceDisplay"].get("z2"), h.main.id, "workspaceDisplay[z2] in state.json")
    h.parked("at")  # z2 is not shown; it is parked on main now
    h.eq(h.shown_on(h.main.name), "w", "workspace on main")


@needs_displays(2)
def test_D4(h):
    """D4 move-to-display sends the window to the workspace shown on the neighbouring display."""
    side = other_display(h, h.main, "next")
    h.eq(side.id, h.side.id, "the neighbour of main")
    h.eq(other_display(h, h.main, "prev").id, h.side.id, "prev from main wraps to the side display too")
    h.cmd("move-to-display next")
    h.eq(h.rec("aw")["workspace"], "x", "workspace of aw")
    h.shown("aw")
    h.maximized("aw")
    h.eq(h.focused_workspace(), "w", "focused workspace")
    focused(h, "aw2")  # focus goes to what remains on main
    # --follow: back to w first, then follow
    h.eq(h.run_on("aw", "move-to-workspace w").code, 0, "move aw back")
    h.settle()
    focus_window(h, "aw")
    h.cmd("move-to-display --follow next")
    h.eq(h.rec("aw")["workspace"], "x", "workspace of aw after --follow")
    h.eq(h.focused_workspace(), "x", "focused workspace after --follow")
    h.shown("aw")
    focused(h, "aw")
    # prev from main wraps to the side display too (two displays)
    focus_window(h, "aw2")
    h.cmd("move-to-display prev")
    h.eq(h.rec("aw2")["workspace"], "x", "workspace of aw2 after prev")
    h.shown("aw2")


@one_display
def test_D5(h):
    """D5 With one display move-to-display is a successful no-op."""
    before = snapshot(h)
    r = h.cmd("move-to-display next")
    h.eq(r.err, "", "stderr")
    h.eq(snapshot(h), before, "status, windows and frames after move-to-display next")


@needs_displays(2)
def test_D6(h):
    """D6 move-workspace-to-display moves the focused workspace, and the old display shows its history."""
    h.eq(h.focused_workspace(), "w", "focused workspace")
    h.cmd("move-workspace-to-display next")
    h.eq(h.display_of("w").id, h.side.id, "display of w")
    h.eq(h.shown_on(h.side.name), "w", "workspace on the side display")
    h.eq(h.shown_on(h.main.name), "c", "workspace on main: another of its workspaces")
    for n in ("aw", "aw2", "te"):
        h.shown(n)
        h.maximized(n)
    h.parked("at")  # x is shown nowhere
    h.shown("ae")
    st = h.state()
    h.eq(st["workspaceDisplay"].get("w"), h.side.id, "workspaceDisplay[w] in state.json")
    h.eq(st["activeWorkspace"].get(str(h.side.id)), "w", "activeWorkspace of the side display in state.json")
    h.cmd("move-workspace-to-display prev")
    h.eq(h.display_of("w").id, h.main.id, "display of w after prev")
    h.eq(h.shown_on(h.main.name), "w", "workspace on main")
    h.eq(h.shown_on(h.side.name), "x", "workspace on the side display: x is back (display history)")
    h.shown("aw")
    h.shown("at")
    h.eq(h.state()["workspaceDisplay"].get("w"), h.main.id, "workspaceDisplay[w] stays in state.json")
    # the state.json override wins over an edited config
    orig = h.config_text
    edited = orig.replace("w = 'main'", "w = 'secondary'", 1)
    h.check(edited != orig, "the test config has no `w = 'main'` line")
    try:
        h.write_config(edited)
        h.settle_os()
        h.cmd("reload-config")
        h.eq(h.display_of("w").id, h.main.id, "display of w after the config edit")
        h.eq(h.shown_on(h.main.name), "w", "workspace on main after the config edit")
        h.shown("aw")
    finally:
        h.write_config(orig)
        h.foci("reload-config")


@needs_displays(2)
def test_D7(h):
    """D7 A display left without a workspace shows `display-N` (N: index in NSScreen.screens)."""
    # with more than two displays `next` would reach another one: the arithmetic below assumes two
    h.check(len(h.displays()) == 2, "D7 is written for exactly two displays")
    h.cmd("focus-display next")
    h.eq(h.focused_workspace(), "x", "focused workspace")
    h.cmd("move-workspace-to-display next")  # x to main
    h.eq(h.display_of("x").id, h.main.id, "display of x")
    h.eq(h.shown_on(h.main.name), "x", "workspace on main")
    h.eq(h.shown_on(h.side.name), "s", "workspace on the side display: s, its other workspace")
    h.shown("at")
    h.shown("ch")
    h.cmd("workspace s")
    h.eq(h.focused_workspace(), "s", "focused workspace")
    h.cmd("move-workspace-to-display next")  # s to main: the side display owns nothing now
    n = [d.id for d in h.displays()].index(h.side.id) + 1  # NSScreen.screens order, not left to right
    name = "display-%d" % n
    h.eq(h.display_of("s").id, h.main.id, "display of s")
    h.eq(h.shown_on(h.main.name), "s", "workspace on main")
    h.eq(h.shown_on(h.side.name), name, "workspace on the side display")
    h.eq(h.state()["workspaceDisplay"].get(name), h.side.id, "workspaceDisplay[%s] in state.json" % name)
    h.eq(h.display_of(name).id, h.side.id, "display of %s" % name)


@needs_displays(2)
def test_D8(h):
    """D8 A floating window moved to the other display is centered there, its size clamped."""
    h.cmd("float")
    vis = h.main.visible
    want_float = Rect(vis.x + vis.w * 0.15, vis.y + vis.h * 0.15, vis.w * 0.7, vis.h * 0.7)
    before = h.frame("aw")
    h.check(before.close_to(want_float, 2), "floating aw is %s, expected 70%% of main centered %s" % (before, want_float))
    h.eq(h.rec("aw")["floating"], True, "floating")
    h.cmd("move-to-display next")
    h.eq(h.rec("aw")["workspace"], "x", "workspace of aw")
    h.shown("aw")
    area = h.side.visible
    w, hh = min(before.w, area.w), min(before.h, area.h)
    want = Rect(area.x + (area.w - w) / 2, area.y + (area.h - hh) / 2, w, hh)
    got = h.frame("aw")
    h.check(got.close_to(want, 2), "aw is %s, expected centered on the side display, clamped: %s" % (got, want))


def test_D9(h):
    """D9 Without a focused managed window, window commands fail with `no focused window`."""
    # spec says Finder with no windows; the unmanaged terminal of the runner has no record either
    h.focus_terminal()
    before = h.windows()
    for script in ("move-to-workspace c", "move-to-display next", "link beta", "link --active", "unlink", "float",
                   "resize +10"):
        h.cmd(script, code=1, err="no focused window")
        h.eq(h.windows(), before, "list-windows after %r" % script)


def test_D10(h):
    """D10 An explicit window is moved even when hidden; reveal brings its project and workspace forward."""
    before = {n: h.frame(n) for n in ("aw", "aw2", "te")}
    r = h.run_on("bw", "move-to-workspace c")
    h.eq(r.code, 0, "run --window exit code")
    h.settle()
    rec = h.rec("bw")
    h.eq((rec["project"], rec["workspace"], rec["visible"]), ("beta", "c", False), "bw (project, workspace, visible)")
    h.parked("bw")
    h.eq(h.project(), "alpha", "project")
    h.eq(h.shown_on(h.main.name), "w", "workspace on main")
    for n, f in before.items():
        h.frame_unchanged(n, f)
    r = h.run_on("bw", "reveal")
    h.eq(r.code, 0, "reveal exit code")
    h.settle()
    h.eq(h.project(), "beta", "project after reveal")
    h.eq(h.shown_on(h.main.name), "c", "workspace on main after reveal")
    h.eq(h.focused_workspace(), "c", "focused workspace")
    h.shown("bw")
    h.maximized("bw")
    h.parked("ae")  # alpha is hidden
    focused(h, "bw")


def test_D11(h):
    """D11 An unknown explicit window: `no window` for reveal, `no focused window` for the other commands."""
    before = snapshot(h)
    r = h.foci("run", "--window", 999999, "reveal")
    h.eq(r.code, 1, "reveal exit code")
    h.check("no window" in r.err, "stderr %r does not contain 'no window'" % r.err.strip())
    for script in ("move-to-workspace c", "move-to-display next", "link beta", "unlink", "float", "resize +10"):
        r = h.foci("run", "--window", 999999, script)
        h.eq(r.code, 1, "%r exit code" % script)
        h.check("no focused window" in r.err, "%r: stderr %r does not contain 'no focused window'" % (script, r.err.strip()))
    r = h.foci("run", "--window", 999999, "move next")
    h.eq(r.code, 1, "move next exit code")
    h.check("no focused tiled window" in r.err, "move next: stderr %r" % r.err.strip())
    h.settle()
    h.eq(snapshot(h), before, "status, windows and frames after the failed commands")


@questionable("a focused window that is parked is not followed again when it is focused again: only a change of "
              "the focused window follows")
def test_D12(h):
    """D12 A focused window that is parked: window commands fail; focusing it again doesn't follow it."""
    h.cmd("project beta")
    focus_window(h, "bw")
    h.cmd("workspace q")
    h.eq(h.shown_on(h.main.name), "q", "workspace on main")
    h.parked("bw")
    h.focused("bw")  # parked and still the focused window
    for script in ("move-to-workspace c", "link --active", "unlink", "float", "resize +10"):
        h.cmd(script, code=1, err="no focused window")
    h.eq(h.rec("bw")["workspace"], "w", "workspace of bw after the failed commands")
    # focusing the same window again: nothing changes (spec: questionable)
    h.probes["pa"].focus(h.wins["bw"].title)
    h.settle_os()
    h.eq(h.shown_on(h.main.name), "q", "workspace on main after focusing bw again")
    h.eq(h.project(), "beta", "project after focusing bw again")
    h.parked("bw")
    # another hidden window does follow: aw belongs to alpha on w
    h.probes["pa"].focus(h.wins["aw"].title)
    h.wait_until(lambda: h.project() == "alpha", 8, "Foci to follow the focus to aw")
    h.settle()
    h.eq(h.shown_on(h.main.name), "w", "workspace on main after following aw")
    h.shown("aw")
    h.parked("bw")
    focused(h, "aw")

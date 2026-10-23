"""I. Minimized, hidden, fullscreen (Tests/E2E/SCENARIOS.md).

A window is frozen when it is minimized, its app is hidden or it is in native fullscreen: Foci keeps its record
but never moves it, and it counts neither as visible nor as a tile.
"""
from harness import Fail, Probe, Rect, fixture


def _adopt(h, name, kind):
    return h.adopt_probe(name, kind)


def _wait_focused(h, name, timeout=6):
    h.wait_focused(name, timeout)


def _wait_frozen(h, name, value, timeout=10):
    """The window may be missing from list-windows for a moment (fullscreen moves it to another Space)."""
    h.wait_until(lambda: (h.wins[name].record or {}).get("frozen") is value, timeout,
                 "%s to have frozen=%s" % (name, value))


def _two_tiles(vis):
    """Frames of two tiles in seq order with gap = 0, side by side on a landscape area, else stacked."""
    if vis.w >= vis.h:
        return (Rect(vis.x, vis.y, vis.w / 2, vis.h), Rect(vis.x + vis.w / 2, vis.y, vis.w / 2, vis.h))
    return (Rect(vis.x, vis.y, vis.w, vis.h / 2), Rect(vis.x, vis.y + vis.h / 2, vis.w, vis.h / 2))


def _workspace_windows(h, ws):
    for w in h.workspaces():
        if w["name"] == ws:
            return w["windows"]
    raise Fail("no workspace %r" % ws)


@fixture("aw")
def test_I1(h):
    """I1 Minimized windows keep their record and are not moved; unminimized, they are parked or laid out."""
    pa = h.probes["pa"]
    title = "alpha - web"
    vis = h.display_of("w").visible
    odd = (vis.x + 100, vis.y + 100, 600, 400)  # a frame that Foci would never plan: a frame call shows

    def minimize():
        h.focus_terminal()  # a minimized focused window would hand the focus to another window of the app
        pa.cmd("minimize", title)
        _wait_frozen(h, "aw", True)
        h.settle_os()

    def unminimize():
        pa.cmd("unminimize", title)
        _wait_frozen(h, "aw", False)
        h.settle_os()

    minimize()
    r = h.rec("aw")
    h.eq((r["project"], r["workspace"], r["frozen"], r["visible"]), ("alpha", "w", True, False),
         "aw (project, workspace, frozen, visible)")
    pa.move(title, *odd)
    h.settle()
    before = h.frame("aw")
    for script in ("project beta", "project alpha"):
        h.cmd(script)
        r = h.rec("aw")
        h.eq((r["project"], r["workspace"], r["frozen"]), ("alpha", "w", True), "aw after %r" % script)
        h.frame_unchanged("aw", before)  # not parked, not laid out: no frame call
    # Unminimized while beta is active: parked on the next refresh.
    h.cmd("project beta")
    unminimize()
    h.eq(h.rec("aw")["project"], "alpha", "aw owner")
    h.parked("aw")
    # Back on alpha it is shown, and minimized and unminimized again while alpha is active it is laid out.
    h.cmd("project alpha")
    h.shown("aw")
    h.maximized("aw")
    minimize()
    pa.move(title, *odd)
    h.settle()
    unminimize()
    h.eq(h.rec("aw")["visible"], True, "aw visible after unminimize")
    h.shown("aw")
    h.maximized("aw")


@fixture("aw", "bw")
def test_I2(h):
    """I2 App hidden (Cmd-H): all its windows are frozen and untouched; unhidden they are shown or parked again."""
    pa = h.probes["pa"]
    before = {n: h.frame(n) for n in ("aw", "bw")}
    pa.cmd("hide")
    for n in ("aw", "bw"):
        _wait_frozen(h, n, True)
    h.settle_os()
    for n in ("aw", "bw"):
        r = h.rec(n)
        h.eq((r["frozen"], r["visible"]), (True, False), "%s (frozen, visible) while hidden" % n)
        h.frame_unchanged(n, before[n])
    h.eq(h.project(), "alpha", "project while hidden")
    pa.cmd("unhide")
    for n in ("aw", "bw"):
        _wait_frozen(h, n, False)
    h.settle_os()
    h.eq(h.project(), "alpha", "project after unhide")
    h.shown("aw")
    h.parked("bw")


@fixture("aw", "aw2")
def test_I3(h):
    """I3 Native fullscreen: the window is frozen and untouched, not a tile; laid out again when it leaves."""
    pa = h.probes["pa"]
    d = h.display_of("w")
    want_aw, want_aw2 = _two_tiles(d.visible)

    def tiled():
        return h.frame("aw").close_to(want_aw, 2) and h.frame("aw2").close_to(want_aw2, 2)

    h.cmd("layout tiles")
    h.wait_until(tiled, 6, "aw and aw2 to be tiles")
    pa.cmd("fullscreen", "alpha - web")
    _wait_frozen(h, "aw", True, timeout=15)
    h.settle_os()
    r = h.rec("aw")
    h.eq((r["project"], r["workspace"], r["frozen"], r["visible"]), ("alpha", "w", True, False),
         "aw (project, workspace, frozen, visible)")
    f = h.frame("aw")
    # Not moved to a tile: a fullscreen window covers its display. (aw2 is in another Space and can't be read.)
    h.check(f.w >= d.frame.w - 2 and f.h >= d.visible.h - 2, "aw in fullscreen is %s, not the display %s" % (f, d.frame))
    pa.cmd("fullscreen", "alpha - web")  # toggles
    _wait_frozen(h, "aw", False, timeout=15)
    h.settle_os(5)
    h.wait_until(tiled, 10, "aw and aw2 to be tiles again after leaving fullscreen")
    h.shown("aw")
    h.shown("aw2")


@fixture("aw", "aw2", "te")
def test_I4(h):
    """I4 Frozen windows don't count: not in the window count, not by `focus next`, `launch web` starts a new one."""
    pa = h.probes["pa"]
    h.eq(_workspace_windows(h, "w"), 3, "windows on w")
    pa.cmd("minimize", "alpha - web 2")
    _wait_frozen(h, "aw2", True)
    h.settle_os()
    h.eq(_workspace_windows(h, "w"), 2, "windows on w with aw2 minimized")
    h.focus_window("aw")  # not h.focused: the reset focus may not have settled
    for script, name in (("focus next", "te"), ("focus next", "aw"), ("focus prev", "te")):
        h.cmd(script)
        _wait_focused(h, name)
    # The only alpha `web` windows are minimized: `launch web` runs the launch command.
    pa.cmd("minimize", "alpha - web")
    _wait_frozen(h, "aw", True)
    h.settle_os()
    h.eq(_workspace_windows(h, "w"), 1, "windows on w with aw and aw2 minimized")
    h.clear_log()
    h.cmd("launch web")
    h.wait_until(lambda: h.log_lines("launch web"), 10, "the launch command to run")
    _adopt(h, "launch-web-alpha", "a")
    h.wait_window("alpha - web", "launch-web-alpha", timeout=15)
    h.settle()
    h.eq(h.log_lines("launch web"), ["launch web alpha"], "launch log")
    h.register("nw", "launch-web-alpha", "alpha - web")
    r = h.rec("nw")
    h.eq((r["project"], r["workspace"], r["frozen"]), ("alpha", "w", False), "new window (project, workspace, frozen)")
    h.eq(_workspace_windows(h, "w"), 2, "windows on w with the new window")

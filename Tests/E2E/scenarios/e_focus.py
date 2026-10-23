"""E. Focus (Tests/E2E/SCENARIOS.md): `focus next|prev` within the workspace, `focus-display`."""
from harness import Fail, needs_displays


def _focused(h, name, timeout=5):
    h.wait_focused(name, timeout)


def _focus(h, name):
    h.focus_window(name)


def _order(h, ws):
    """Fixture windows that are shown on `ws` (not frozen), in Foci's order (`seq` from state.json)."""
    recs = h.windows()
    windows = h.state().get("windows", {})
    out = []
    for n, w in h.wins.items():
        for r in recs:
            if r["pid"] == w.pid and r["title"] == w.title and r["workspace"] == ws and r["visible"] \
                    and not r["frozen"]:
                out.append((windows.get(str(r["id"]), {}).get("seq", 0), n))
    return [n for _, n in sorted(out)]


def test_E1(h):
    """E1 Focus next/prev cycles within the workspace, in seq order; other projects and workspaces are skipped."""
    h.eq(_order(h, "w"), ["aw", "aw2", "te"], "seq order on w (bw is beta's and parked)")
    _focused(h, "aw")
    for want in ("aw2", "te", "aw"):  # wraps after the last
        h.cmd("focus next")
        _focused(h, want)
    for want in ("te", "aw2", "aw"):  # prev goes back and wraps before the first
        h.cmd("focus prev")
        _focused(h, want)
    h.eq(h.focused_workspace(), "w", "focused workspace")


def test_E2(h):
    """E2 Frozen (minimized) windows are skipped by focus next."""
    pa = h.probes["pa"]
    pa.cmd("minimize", "alpha - web 2")
    try:
        h.wait_until(lambda: h.rec("aw2")["frozen"], 6, "aw2 to be frozen")
        h.settle()
        h.eq(_order(h, "w"), ["aw", "te"], "windows of w that count")
        _focus(h, "aw")
        for want in ("te", "aw", "te"):  # aw2 never gets focus
            h.cmd("focus next")
            _focused(h, want)
        h.cmd("focus prev")
        _focused(h, "aw")
        h.eq(h.rec("aw2")["frozen"], True, "aw2 still frozen")
    finally:
        try:
            pa.cmd("unminimize", "alpha - web 2")
        except Exception:  # noqa: BLE001 - the next reset restarts the fixture anyway
            pass


def test_E3(h):
    """E3 Nothing managed focused: focus next goes to the first window."""
    _focus(h, "aw2")  # not the first one, so that "first" is not what was focused before
    h.focus_terminal()  # the runner's terminal is unmanaged: nothing in the list is focused
    h.cmd("focus next")
    _focused(h, "aw")  # first of w in seq order (not aw2, which was focused last)
    h.eq(h.focused_workspace(), "w", "focused workspace")
    if h.side is not None:
        # A window of the other display's workspace focused: the focused workspace follows the focus (at the next
        # refresh, which `foci` itself triggers) before `focus next` looks at the list, so it goes to the first
        # window of x. Spec: "focus next goes to the first, too": the same, as x has one alpha window.
        _focus(h, "at")
        h.cmd("focus next")
        _focused(h, "at")
        h.eq(h.focused_workspace(), "x", "focused workspace after focusing at")


@needs_displays(2)
def test_E4(h):
    """E4 focus-display moves to the other display's workspace and focuses its last focused window."""
    _focused(h, "aw")
    h.cmd("focus-display next")
    h.eq(h.focused_workspace(), "x", "focused workspace after focus-display next")
    _focused(h, "at")  # the only alpha window on x
    h.cmd("focus-display prev")
    h.eq(h.focused_workspace(), "w", "focused workspace after focus-display prev")
    _focused(h, "aw")
    # Now with a choice on both displays: the last focused window wins, not the first.
    h.probes["at"].new_window("alpha term 2")
    h.wait_window("alpha term 2", "at")
    h.register("at2", "at", "alpha term 2")
    h.settle()
    _focus(h, "aw2")
    _focus(h, "at2")
    h.eq(h.focused_workspace(), "x", "focused workspace after focusing at2")
    h.cmd("focus-display prev")
    h.eq(h.focused_workspace(), "w", "focused workspace")
    _focused(h, "aw2")
    h.cmd("focus-display next")
    h.eq(h.focused_workspace(), "x", "focused workspace")
    _focused(h, "at2")

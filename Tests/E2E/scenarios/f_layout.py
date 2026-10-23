"""F. Layout (Tests/E2E/SCENARIOS.md): maximized and tiles, move, resize, balance, float, drags, config.

Geometry comes from `h.main` / `h.side` (Accessibility coordinates, `visible` = without menu bar and Dock), never from
hard-coded numbers. The test config has `gap = 0`; scenarios that need a gap rewrite the config (`_with_gap`) and
put the test config back in a `finally`.
"""
import time

from harness import Fail, Rect, fixture, needs_displays

# ---------------------------------------------------------------------- private helpers


def _focused(h, name, timeout=5):
    h.wait_focused(name, timeout)


def _focus(h, name):
    h.focus_window(name)


def _order(h, ws, tiles_only=False):
    """Fixture windows shown on `ws` (not frozen), in Foci's order (`seq` from state.json)."""
    recs = h.windows()
    windows = h.state().get("windows", {})
    out = []
    for n, w in h.wins.items():
        for r in recs:
            if r["pid"] == w.pid and r["title"] == w.title and r["workspace"] == ws and r["visible"] \
                    and not r["frozen"] and not (tiles_only and r["floating"]):
                out.append((windows.get(str(r["id"]), {}).get("seq", 0), n))
    return [n for _, n in sorted(out)]


def _weights(h, names):
    windows = h.state().get("windows", {})
    return [windows[str(h.wins[n].id)].get("weight", 1) for n in names]


def _horizontal(area):
    """Planner.isHorizontal with auto orientation: side by side unless the area is portrait."""
    return area.w >= area.h


def _tiles(area, weights, gap, horizontal):
    """Planner.layoutFrames: `area` is the visible frame already inset by `gap`."""
    n = len(weights)
    length = (area.w if horizontal else area.h) - gap * (n - 1)
    total = float(sum(weights))
    off = area.x if horizontal else area.y
    out = []
    for wt in weights:
        size = length * wt / total
        out.append(Rect(off, area.y, size, area.h) if horizontal else Rect(area.x, off, area.w, size))
        off += size + gap
    return out


def _frame_ok(name, got, want, tol):
    """TextEdit's windows have a minimum height (about 520 pt): a smaller tile makes it taller than asked."""
    if name == "te" and want.h < got.h and got.h > 400:
        return Rect(got.x, got.y, got.w, want.h).close_to(want, tol)
    return got.close_to(want, tol)


def _expect_frames(h, want, timeout=6.0, tol=2.0):
    """Polls until every window `name -> Rect` is there (moves are asynchronous), else fails with all the frames."""
    deadline = time.time() + timeout
    while True:
        got = {n: h.frame(n) for n in want}
        bad = [n for n in want if not _frame_ok(n, got[n], want[n], tol)]
        if not bad:
            return
        if time.time() > deadline:
            raise Fail("; ".join("%s: frame %s, expected %s" % (n, got[n], want[n]) for n in bad))
        time.sleep(0.2)


def _expect_tiles(h, names, display, gap, weights=None, horizontal=None):
    """The windows are tiles of `display`, in this order. Defaults: equal weights, orientation by the display."""
    area = display.visible.inset(gap)
    if horizontal is None:
        horizontal = _horizontal(area)
    frames = _tiles(area, weights or [1] * len(names), gap, horizontal)
    _expect_frames(h, dict(zip(names, frames)))


def _expect_maximized(h, names, gap=0):
    for n in names:
        d = h.display_of(h.rec(n)["workspace"])
        _expect_frames(h, {n: d.visible.inset(gap)})


GAP = 40  # not 10: macOS keeps a window within ~20 pt of the full height at the full height (an AX resize of a
# maximized window to height - 20 is ignored), so a small gap can't be told from a Foci bug; 40 is clear of that.


def _with_gap(h, gap):
    """Rewrites the test config with another gap and reloads it. Pair with `_restore_config` in a finally."""
    base = h.base_config()
    assert "gap = 0" in base
    h.write_config(base.replace("gap = 0", "gap = %d" % gap, 1))
    h.cmd("reload-config")
    h.settle_os()


def _restore_config(h):
    h.write_config()
    h.foci("reload-config")
    h.settle_os()


def _layout_of(h, ws):
    for w in h.workspaces():
        if w["name"] == ws:
            return w["layout"]
    raise Fail("no workspace %r in list-workspaces" % ws)


# ---------------------------------------------------------------------- scenarios


def test_F1(h):
    """F1 Maximized by default: every shown, non-floating window fills the visible frame, inset by the gap."""
    names = ["aw", "aw2", "te"] + (["at"] if h.side is not None else [])
    for n in names:
        h.eq(h.rec(n)["visible"], True, "%s visible" % n)
    _expect_maximized(h, names, 0)
    try:
        _with_gap(h, GAP)
        _expect_maximized(h, names, GAP)
    finally:
        _restore_config(h)
    _expect_maximized(h, names, 0)


def test_F2(h):
    """F2 Tiles side by side on landscape: equal columns in seq order, full height of the visible frame."""
    h.cmd("layout tiles")
    order = _order(h, "w")
    h.eq(order, ["aw", "aw2", "te"], "seq order on w")
    h.eq(_layout_of(h, "w"), "tiles", "layout of w")
    _expect_tiles(h, order, h.main, 0)  # no gap: three equal columns
    try:
        _with_gap(h, GAP)  # gap between and around the tiles
        _expect_tiles(h, order, h.main, GAP)
    finally:
        _restore_config(h)
    _expect_tiles(h, order, h.main, 0)


@needs_displays(2)
def test_F3(h):
    """F3 Tiles stacked on a portrait display (rows), side by side on a landscape one."""
    side = h.side
    h.probes["at"].new_window("alpha term 2")
    h.wait_window("alpha term 2", "at")
    h.register("at2", "at", "alpha term 2")
    h.cmd("workspace x; layout tiles")
    order = _order(h, "x")
    h.eq(order, ["at", "at2"], "seq order on x")
    portrait = side.visible.w < side.visible.h
    if portrait:  # the spec's case
        _expect_tiles(h, order, side, 0, horizontal=False)
    else:
        # Spec: "[2D, side portrait]: rows". This Mac's side display is landscape, so auto gives columns there; the
        # stacking itself is checked with an explicit orientation (toggle-orientation, as in F4).
        _expect_tiles(h, order, side, 0, horizontal=True)
        h.cmd("layout toggle-orientation")
        _expect_tiles(h, order, side, 0, horizontal=False)


def test_F4(h):
    """F4 layout toggle flips tiles and maximized; toggle-orientation stacks, then goes back to side by side."""
    names = ["aw", "aw2", "te"]
    area = h.main.visible
    h.eq(_layout_of(h, "w"), "maximized", "layout of w at the start")
    h.cmd("layout toggle")
    h.eq(_layout_of(h, "w"), "tiles", "layout after the first toggle")
    _expect_tiles(h, names, h.main, 0)
    h.cmd("layout toggle")
    h.eq(_layout_of(h, "w"), "maximized", "layout after the second toggle")
    _expect_maximized(h, names)
    # toggle-orientation on maximized: tiles, against what the display would pick by itself (landscape: stacked).
    h.cmd("layout toggle-orientation")
    h.eq(_layout_of(h, "w"), "tiles", "layout after toggle-orientation")
    _expect_tiles(h, names, h.main, 0, horizontal=not _horizontal(area))
    h.cmd("layout toggle-orientation")  # again: side by side
    _expect_tiles(h, names, h.main, 0, horizontal=_horizontal(area))


def test_F5(h):
    """F5 move swaps the focused tile with its neighbour; wraps; the order persists; floating windows can't move."""
    def check(want, focus=True):
        h.eq(_order(h, "w", tiles_only=True), want, "tile order")
        _expect_tiles(h, want, h.main, 0)
        if focus:
            _focused(h, "aw")

    h.cmd("layout tiles")
    check(["aw", "aw2", "te"])
    h.cmd("move next")
    check(["aw2", "aw", "te"])
    h.cmd("move prev")
    check(["aw", "aw2", "te"])
    h.cmd("move prev")  # wraps: aw swaps with the last one
    check(["te", "aw2", "aw"])
    # A floating focused window is not a tile.
    h.cmd("float")
    h.cmd("move next", code=1, err="no focused tiled window")
    h.cmd("float")
    check(["te", "aw2", "aw"])
    # The order survives project switches and a restart.
    h.cmd("project beta")
    h.cmd("project alpha")
    check(["te", "aw2", "aw"])
    h.restart_foci()
    h.settle_os()
    check(["te", "aw2", "aw"], focus=False)


@fixture("aw", "bw", "aw2")
def test_F6(h):
    """F6 resize grows the focused tile by points, between 5 % and 95 %; no-op in maximized or with one tile."""
    area = h.main.visible
    length = area.w  # gap 0: the whole width is shared by the tiles
    names = ["aw", "aw2"]
    h.cmd("layout tiles")
    h.eq(_order(h, "w", tiles_only=True), names, "tile order")
    _focused(h, "aw")
    _expect_tiles(h, names, h.main, 0)
    h.cmd("resize +200")  # the focused tile grows by 200, the other shrinks by 200
    _expect_frames(h, {"aw": Rect(area.x, area.y, length / 2 + 200, area.h),
                       "aw2": Rect(area.x + length / 2 + 200, area.y, length / 2 - 200, area.h)})
    h.cmd("resize -200")
    _expect_tiles(h, names, h.main, 0)
    for _ in range(4):
        h.cmd("resize +1000")
    wa, wb = _weights(h, names)
    h.check(abs(wa / (wa + wb) - 0.95) < 0.001, "share of aw is %g, expected 0.95" % (wa / (wa + wb)))
    _expect_frames(h, {"aw": Rect(area.x, area.y, length * 0.95, area.h)})  # the small tile may hit a minimum size
    for _ in range(8):
        h.cmd("resize -1000")
    wa, wb = _weights(h, names)
    h.check(abs(wa / (wa + wb) - 0.05) < 0.001, "share of aw is %g, expected 0.05" % (wa / (wa + wb)))
    _expect_frames(h, {"aw2": Rect(area.x + length * 0.05, area.y, length * 0.95, area.h)})
    # Maximized: exit 0, nothing changes.
    before = _weights(h, names)
    h.cmd("layout maximized")
    h.cmd("resize +200")
    _expect_maximized(h, names)
    h.eq(_weights(h, names), before, "weights after resize in maximized")
    # One tile (beta has only bw on w): exit 0, nothing changes.
    h.cmd("project beta")
    h.cmd("layout tiles")
    h.eq(_order(h, "w", tiles_only=True), ["bw"], "tiles under beta")
    h.cmd("resize +200")
    _expect_frames(h, {"bw": area})
    h.eq(_weights(h, ["bw"]), [1], "weight of the only tile")


@needs_displays(2)
def test_F7(h):
    """F7 balance makes the tiles of the focused workspace equal and leaves other workspaces alone."""
    names = ["aw", "aw2", "te"]
    h.cmd("layout tiles")
    _focused(h, "aw")
    h.cmd("resize +200")
    wa = _weights(h, names)
    h.check(len(set(round(x, 6) for x in wa)) > 1, "resize did not change the weights: %s" % wa)
    _expect_tiles(h, names, h.main, 0, weights=wa)
    # x gets its own unequal weights (at and a second window).
    h.probes["at"].new_window("alpha term 2")
    h.wait_window("alpha term 2", "at")
    h.register("at2", "at", "alpha term 2")
    h.cmd("workspace x; layout tiles")
    h.eq(_order(h, "x"), ["at", "at2"], "seq order on x")
    _focus(h, "at")
    h.cmd("resize +200")
    wx = _weights(h, ["at", "at2"])
    h.check(abs(wx[0] - wx[1]) > 0.01, "resize on x did not change the weights: %s" % wx)
    h.cmd("workspace w")
    _focused(h, "aw")
    h.cmd("balance")
    h.eq(_weights(h, names), [1, 1, 1], "weights on w after balance")
    _expect_tiles(h, names, h.main, 0)
    h.eq(_weights(h, ["at", "at2"]), wx, "weights on x untouched by balance")
    _expect_tiles(h, ["at", "at2"], h.side, 0, weights=wx)


def test_F8(h):
    """F8 float: 70 % of the visible frame, centered, focused; the tiles re-split; float again returns to the tiles."""
    v = h.main.visible
    h.cmd("layout tiles")
    h.eq(_order(h, "w"), ["aw", "aw2", "te"], "seq order on w")
    _focus(h, "aw2")
    h.cmd("float")
    h.eq(h.rec("aw2")["floating"], True, "aw2 floating")
    _expect_frames(h, {"aw2": Rect(v.x + v.w * 0.15, v.y + v.h * 0.15, v.w * 0.7, v.h * 0.7)})
    _focused(h, "aw2")
    _expect_tiles(h, ["aw", "te"], h.main, 0)  # the other two share the space
    h.cmd("float")  # back into the tiles at its old position (seq is unchanged)
    h.eq(h.rec("aw2")["floating"], False, "aw2 floating after the second float")
    _expect_tiles(h, ["aw", "aw2", "te"], h.main, 0)
    _focused(h, "aw2")


def test_F9(h):
    """F9 The floating frame is remembered across project and workspace switches and a restart; re-centered
    when dragged onto the other display."""
    v = h.main.visible
    _focus(h, "aw2")
    h.cmd("float")
    want = Rect(v.x + 40, v.y + 40, 900, 600)
    h.drag("aw2", want.x, want.y, want.w, want.h)
    h.settle_os()  # Foci captures the frame at a refresh, while the window is shown and on screen
    _expect_frames(h, {"aw2": want})
    # Another project: aw2 is parked. A refresh while it is parked must not capture the parked frame.
    h.cmd("project beta")
    h.settle_os()
    h.parked("aw2")
    h.cmd("project alpha")
    _expect_frames(h, {"aw2": want})
    # Another workspace on main.
    h.cmd("workspace c")
    h.settle_os()
    h.parked("aw2")
    h.cmd("workspace w")
    _expect_frames(h, {"aw2": want})
    # A restart (the quit puts it back on screen, the state keeps the frame).
    h.restart_foci()
    h.settle_os()
    _expect_frames(h, {"aw2": want})
    if h.side is not None:
        # Dragged onto the other display (still on screen): re-centered on its own workspace's display.
        sv = h.side.visible
        w, hh = min(900, sv.w - 120), min(600, sv.h - 120)
        h.drag("aw2", sv.x + 60, sv.y + 60, w, hh)
        h.settle_os()
        _expect_frames(h, {"aw2": Rect(v.x + (v.w - w) / 2, v.y + (v.h - hh) / 2, w, hh)})
        h.shown("aw2")


def test_F10(h):
    """F10 User drags and resizes of managed windows snap back to the planned frame at the next refresh."""
    v = h.main.visible
    # Maximized: a drag, a resize; the 2 s timer refresh puts them back.
    h.drag("aw", v.x + 100, v.y + 100, 500, 400)
    h.check(not h.frame("aw").close_to(v), "the drag did not take")
    h.settle_os()
    _expect_frames(h, {"aw": v})
    h.drag("aw", v.x, v.y, 600, 500)
    h.settle_os()
    _expect_frames(h, {"aw": v})
    # Tiles: any refresh, here a focus change.
    h.cmd("layout tiles")
    names = ["aw", "aw2", "te"]
    area = h.main.visible
    h.drag("aw2", area.x + 50, area.y + 50, 400, 300)
    h.check(not h.frame("aw2").close_to(_tiles(area, [1, 1, 1], 0, _horizontal(area))[1]), "the drag did not take")
    _focus(h, "aw")
    _expect_tiles(h, names, h.main, 0)
    h.drag("aw", area.x, area.y, area.w / 2, area.h / 2)  # a resize
    _focus(h, "aw2")
    _expect_tiles(h, names, h.main, 0)


def test_F11(h):
    """F11 Windows coming and going re-tile: a new window joins at the end, closing the middle one closes the gap."""
    h.cmd("layout tiles")
    h.eq(_order(h, "w"), ["aw", "aw2", "te"], "seq order on w")
    h.probes["pa"].new_window("alpha - web 4")  # an alpha web window by the title rule
    h.wait_window("alpha - web 4", "pa")
    h.register("aw3", "pa", "alpha - web 4")
    h.settle()
    h.eq(h.rec("aw3")["project"], "alpha", "new window owner")
    h.eq(_order(h, "w"), ["aw", "aw2", "te", "aw3"], "the new window joins at the end")
    _expect_tiles(h, ["aw", "aw2", "te", "aw3"], h.main, 0)
    h.probes["pa"].close_window("alpha - web 2")  # the second one
    h.wait_gone("alpha - web 2", "pa")
    h.settle_os()
    del h.wins["aw2"]
    h.eq(_order(h, "w"), ["aw", "te", "aw3"], "tile order after the close")
    _expect_tiles(h, ["aw", "te", "aw3"], h.main, 0)


def test_F12(h):
    """F12 Initial layout from the config: a project that never set the workspace's layout gets the config's;
    one that did keeps its runtime choice."""
    base = h.base_config()
    assert "c = 'main'\n" in base and "s = 'secondary'\n" in base
    text = base.replace("c = 'main'\n", "", 1).replace(
        "s = 'secondary'\n", "s = 'secondary'\n\n[workspaces.c]\ndisplay = 'main'\nlayout = 'tiles'\n", 1)
    h.check(text != base, "the config was not changed")
    # alpha chooses a layout for c at runtime (maximized, as before the change); beta has two windows there.
    h.cmd("move-to-workspace --follow c")  # aw
    h.eq(h.focused_workspace(), "c", "focused workspace")
    h.cmd("layout maximized")
    for n in ("bw", "bt"):
        r = h.run_on(n, "move-to-workspace c")
        h.eq(r.code, 0, "move-to-workspace c of %s" % n)
    h.settle()
    h.eq(sorted(_order(h, "c")), ["ae", "aw"], "alpha's windows on c")
    _expect_maximized(h, ["ae", "aw"])
    h.cmd("project beta")
    beta = _order(h, "c")
    h.eq(sorted(beta), ["bt", "bw"], "beta's windows on c")
    _expect_maximized(h, beta)  # the default layout, before the config change
    h.cmd("project alpha")
    try:
        h.write_config(text)
        h.cmd("reload-config")
        h.settle_os()
        h.cmd("project beta")
        h.eq(_layout_of(h, "c"), "tiles", "layout of c under beta")
        _expect_tiles(h, _order(h, "c"), h.main, 0)  # never set: the config's tiles
        h.cmd("project alpha")
        h.eq(_layout_of(h, "c"), "maximized", "layout of c under alpha")
        _expect_maximized(h, ["ae", "aw"])  # its runtime choice wins
    finally:
        _restore_config(h)

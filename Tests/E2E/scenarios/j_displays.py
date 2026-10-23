"""J. Displays (Tests/E2E/SCENARIOS.md).

Most of these need a person: a cable pulled, a lid closed, a display added in System Settings. They are marked
@manual and always skipped by the runner, but each body is a real script: a person (or a virtual display tool)
removes the `@manual` mark, starts the runner and does what the console asks. The steps that wait for the person
print a line starting with `[manual]` and poll the display count (`NSScreen`) for up to 5 minutes.

J5 has an automated half that runs on every two-display setup: parking corners and `focus-display` order are
checked against the arrangement the Mac has right now. Changing the arrangement itself stays manual.

On this Mac the side display is BELOW the main one, so parking uses the "no display to the right" corner
(`x = maxX - 1`). All geometry comes from `h.displays()`, `h.main` and `h.side`.
"""
import subprocess

from harness import close, displays_now, known_issue, manual, needs_displays

ALL = ("aw", "bw", "aw2", "at", "bt", "ae", "ch", "te")


def _say(msg):
    print("\n  [manual] " + msg, flush=True)


def _count_displays():
    try:
        return len(displays_now())
    except Exception:  # noqa: BLE001 - without displays NSScreen/osascript can fail
        return 0


def _wait_display_count(h, n, what, timeout=300):
    """Tells the person what to do and polls until `n` displays are connected. Refreshes the harness cache."""
    _say(what)
    h.wait_until(lambda: _count_displays() == n, timeout, what, interval=1.0)
    h.displays(refresh=True)


def _right_of(h, d):
    """Another display is to the right of `d` (the spec's parking rule)."""
    return any(o.id != d.id and o.frame.x >= d.frame.maxx - 1 for o in h.displays())


def _expected_park_x(h, d, width):
    return d.frame.x - width + 1 if _right_of(h, d) else d.frame.maxx - 1


def _unplug_side(h):
    """J1 steps 1-2: focus `x` on the side display, ask for the side display to be disconnected, settle.
    Returns the old side `Display`."""
    side = h.side
    h.check(side is not None, "this scenario needs a second display")
    n = len(h.displays())
    h.cmd("workspace x")  # `x` lives on the side display and gets the focus
    _wait_display_count(h, n - 1, "disconnect the side display %r" % side.name)
    h.settle_os()
    return side


def _check_unplugged(h, old_side):
    """J1 expectations: `x` and `s` are on main, `x` is shown and focused with `at`, `w` is parked."""
    main = h.main
    h.check(h.side is None or h.side.id != old_side.id, "the side display is still connected")
    h.eq(h.focused_workspace(), "x", "focused workspace")
    h.eq(h.shown_on(main.name), "x", "workspace shown on main")
    for ws in ("x", "s"):
        h.eq(h.display_of(ws).id, main.id, "display of %s" % ws)
    h.shown("at")
    h.maximized("at")
    h.focused("at")
    for n in ("aw", "bw", "aw2", "te", "bt", "ae", "ch"):  # `w` is not shown any more, `s`/`c` never were
        h.parked(n)
    # Nothing is left on the old side display: whatever is shown is on main.
    for n in ALL:
        if h.rec(n)["visible"]:
            cx, cy = h.frame(n).center
            h.check(main.frame.contains(cx, cy), "%s is shown at %s, off main %s" % (n, h.frame(n), main.frame))


@manual("needs a display to be unplugged (or a virtual display to be removed)")
@needs_displays(2)
def test_J1(h):
    """J1 Disconnect a display: its workspaces move to main, the focused one with its windows."""
    old_side = _unplug_side(h)
    _check_unplugged(h, old_side)


@manual("needs a display to be unplugged and plugged in again")
@needs_displays(2)
def test_J2(h):
    """J2 Reconnect: the side display shows `x` again (display history), main shows `w` again with its windows."""
    old_side = _unplug_side(h)  # same start as J1: `x` focused on the side display, then it goes away
    _check_unplugged(h, old_side)
    _wait_display_count(h, 2, "reconnect the side display")
    h.settle_os()
    side = h.side
    h.check(side is not None, "the side display did not come back")
    h.eq(h.shown_on(side.name), "x", "workspace on the side display")
    h.eq(h.shown_on(h.main.name), "w", "workspace on main")
    h.eq(h.display_of("x").id, side.id, "display of x")
    h.eq(h.display_of("s").id, side.id, "display of s")
    for n in ("aw", "aw2", "te", "at"):
        h.shown(n)
    for n in ("bw", "bt", "ae", "ch"):
        h.parked(n)
    h.maximized("at")


@manual("needs the lid closed with no external display; the machine sleeps, so nothing can run meanwhile")
def test_J3(h):
    """J3 Sleep / no displays: no frames change while asleep, state is unchanged, commands answer `no displays`."""
    names = list(ALL)
    frames = {n: h.frame(n) for n in names}
    state = h.state()
    status = h.status()
    # A probe loop that runs while the Mac sleeps: `mode main` is a no-op for Foci, but `run` checks the displays
    # first. Its exit codes and stderr go to a file the scenario reads after the wake-up.
    out = h.e2e / "j3-probe.txt"
    out.write_text("")
    loop = ('for i in $(seq 1 600); do "%s" mode main >/dev/null 2>>"%s"; echo "exit $?" >>"%s"; sleep 1; done'
            % (h.foci_bin, out, out))
    proc = subprocess.Popen(["/bin/sh", "-c", loop], env=h.environment(), stdin=subprocess.DEVNULL,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        _say("close the lid (no external display), wait until the Mac sleeps, then wake it up")
        h.wait_until(lambda: "no displays" in out.read_text(), 300, "a command to answer 'no displays'", interval=2.0)
        h.wait_until(lambda: _count_displays() > 0, 300, "the displays to come back", interval=2.0)
    finally:
        proc.kill()
        proc.wait()
    h.displays(refresh=True)
    h.settle_os()
    answers = out.read_text()
    h.check("exit 1" in answers, "no command exited 1 during the gap: %r" % answers[-200:])
    for n in names:
        h.frame_unchanged(n, frames[n], tol=2)
    h.eq(h.status(), status, "status after the wake-up")
    now = h.state()
    for key in ("activeProject", "workspaceDisplay", "activeWorkspace", "focusedWorkspace", "layouts"):
        h.eq(now.get(key), state.get(key), "state.json %s" % key)


@manual("needs a third display to be connected")
@needs_displays(2)
def test_J4(h):
    """J4 New display with nothing to show: it shows `display-N`; ad hoc workspaces created there live on it."""
    before = {d.id for d in h.displays()}
    _wait_display_count(h, len(before) + 1, "connect a third display")
    h.settle_os()
    shown = [d for d in h.displays() if d.id not in before]
    h.eq(len(shown), 1, "new displays")
    new = shown[0]
    name = "display-%d" % (h.displays().index(new) + 1)  # N is the index in the system order, not left to right
    h.eq(h.shown_on(new.name), name, "workspace on the new display")
    h.cmd("workspace " + name)
    h.eq(h.focused_workspace(), name, "focused workspace after `workspace %s`" % name)
    h.cmd("workspace q4")  # created while focused on the new display
    h.eq(h.display_of("q4").id, new.id, "display of the ad hoc workspace")
    h.eq(h.shown_on(new.name), "q4", "workspace on the new display")
    ws = h.state()["workspaceDisplay"]
    h.eq(ws.get("q4"), new.id, "workspaceDisplay of q4")
    h.eq(ws.get(name), new.id, "workspaceDisplay of %s" % name)
    # The old displays are untouched.
    h.eq(h.shown_on(h.main.name), "w", "workspace on main")


@needs_displays(2)
def test_J5(h):
    """J5 Arrangement: parking corners and focus-display order follow the arrangement as it is now.

    Automated half only. The spec step "move `side` to the left of `main` in System Settings" is manual: do it,
    run `-k J5` again and the same checks cover the new arrangement (parking corners flip, `focus-display`
    follows the new left-to-right order).
    """
    displays = h.displays(refresh=True)
    # Parked windows: beta's windows and the workspaces that are not shown (c on main, s on side).
    for n in ("bw", "ae", "bt", "ch"):
        h.parked(n)  # also checks that no part but 1pt shows on any display
        r = h.rec(n)
        d = h.display_of(r["workspace"])
        f = h.frame(n)
        want = _expected_park_x(h, d, f.w)
        h.check(close(f.x, want),
                "%s is parked at x=%g on %s, the arrangement wants x=%g (%s of it)" % (
                    n, f.x, d.name, want, "a display to the right" if _right_of(h, d) else "no display to the right"))
        h.check(f.y >= d.frame.maxy - 31, "%s is parked at y=%g, not at the bottom of %s" % (n, f.y, d.name))

    # focus-display goes by frame.x (stable for equal x, main first): next, next, prev, prev walk the ring.
    order = sorted(displays, key=lambda d: d.frame.x)

    def expect(direction):
        cur = h.display_of(h.focused_workspace())
        i = [d.id for d in order].index(cur.id)
        return order[(i + (1 if direction == "next" else -1)) % len(order)]

    for direction in ("next", "next", "prev", "prev"):
        want = expect(direction)
        h.cmd("focus-display " + direction)
        ws = h.focused_workspace()
        h.eq(h.shown_on(want.name), ws, "focus-display %s: focused workspace is not the one shown on %s" % (
            direction, want.name))
    h.eq(h.focused_workspace(), "w", "back on w after the round trip")


@manual("needs two different displays to be connected one after the other at the same display index")
@known_issue("display-N is stored in workspaceDisplay: a different display that needs a placeholder at the same "
             "index gets the same name, and the windows on it move there")
@needs_displays(2)
def test_J6(h):
    """J6 A display-N name can be reused by a new display (known issue, pinned as it is)."""
    before = {d.id for d in h.displays()}
    _wait_display_count(h, len(before) + 1, "connect a third display A")
    h.settle_os()
    a = [d for d in h.displays() if d.id not in before][0]
    name = "display-%d" % (h.displays().index(a) + 1)
    h.eq(h.shown_on(a.name), name, "placeholder on display A")
    r = h.run_on("aw", "move-to-workspace " + name)  # a window lives on the placeholder
    h.eq(r.code, 0, "move-to-workspace exit code")
    h.settle()
    h.shown("aw")
    h.eq(h.display_of(name).id, a.id, "display of %s while A is connected" % name)
    h.eq(h.state()["workspaceDisplay"][name], a.id, "workspaceDisplay of %s" % name)

    known = {d.id for d in h.displays()} - {a.id}
    _wait_display_count(h, len(known) + 1,
                        "disconnect display A and connect a different display B so that it takes the same index")
    h.settle_os()
    b = [d for d in h.displays() if d.id not in known][0]
    h.check(b.id != a.id, "display B must be a different display than A")
    h.eq(h.displays().index(b) + 1, int(name.split("-")[1]), "index of display B")
    # Known issue: the name is pointed at B and `aw` moves there. A fix would keep A's workspace on main.
    h.eq(h.state()["workspaceDisplay"][name], b.id, "workspaceDisplay of %s (known issue: re-pointed to B)" % name)
    h.eq(h.display_of(name).id, b.id, "display of %s (known issue: it is B now)" % name)
    h.eq(h.rec("aw")["workspace"], name, "workspace of aw")
    h.shown("aw")

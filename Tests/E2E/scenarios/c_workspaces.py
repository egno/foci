"""C. Workspaces (Tests/E2E/SCENARIOS.md).

The side display of the test Mac can be below `main`, not to its right: all geometry comes from `h.displays()`,
`h.main` and `h.side`. Neighbour order for `focus-display` is by `frame.x`, like `Engine.neighbour`.
"""
import os

from harness import Probe, close, needs_displays, questionable


# ---------------------------------------------------------------------- private helpers


def other_display(h, d, direction="next"):
    """The display `focus-display <direction>` reaches from `d`: displays sorted by frame.x, wrapping."""
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


def adopt_probe(h, key, ctl, kind="b"):
    """A Probe that Foci launched (its control socket is `$E2E_DIR/ctl/<ctl>.sock`), as `h.probes[key]`."""
    h.probes[key] = Probe(ctl, str(h.ctl / (ctl + ".sock")), kind)
    h.wait_probe(key)
    return h.probes[key]


def workspace_entry(h, name):
    for w in h.workspaces():
        if w["name"] == name:
            return w
    return None


def parked_x(h, d, width):
    """Planner.parkedFrame: `d.x - width + 1` with another display to the right, else `d.maxX - 1`."""
    right = any(o.id != d.id and o.frame.x >= d.frame.maxx - 1 for o in h.displays())
    return d.frame.x - width + 1 if right else d.frame.maxx - 1


# ---------------------------------------------------------------------- scenarios


@needs_displays(2)
def test_C1(h):
    """C1 Switching a workspace changes only its own display."""
    h.cmd("workspace c")
    h.eq(h.shown_on(h.main.name), "c", "workspace on main")
    h.eq(h.shown_on(h.side.name), "x", "workspace on the side display")
    h.eq(h.focused_workspace(), "c", "focused workspace")
    h.shown("ae")
    h.shown("at")
    for n in ("aw", "te"):
        h.parked(n)
    focused(h, "ae")
    h.eq(h.state().get("previousWorkspace"), "w", "previousWorkspace in state.json")


@needs_displays(2)
def test_C2(h):
    """C2 Switching to a workspace of the other display moves focus there."""
    h.cmd("workspace s")
    h.eq(h.shown_on(h.side.name), "s", "workspace on the side display")
    h.eq(h.shown_on(h.main.name), "w", "workspace on main")
    h.eq(h.focused_workspace(), "s", "focused workspace")
    h.shown("ch")
    h.maximized("ch")
    h.parked("at")  # x is no longer shown
    h.shown("aw")
    focused(h, "ch")


@needs_displays(2)
def test_C3(h):
    """C3 An ad hoc workspace lives on the display it was first used on and stays there."""
    h.cmd("workspace x")  # focus on the side display
    h.eq(h.focused_workspace(), "x", "focused workspace")
    h.cmd("workspace q")
    h.eq(h.shown_on(h.side.name), "q", "workspace on the side display")
    h.eq(h.display_of("q").id, h.side.id, "display of q")
    q = workspace_entry(h, "q")
    h.eq((q["windows"], q["shown"], q["focused"]), (0, True, True), "q (windows, shown, focused)")
    h.parked("at")  # x is hidden
    h.eq(h.state()["workspaceDisplay"].get("q"), h.side.id, "workspaceDisplay[q] in state.json")
    h.cmd("workspace w")  # focus goes back to main
    h.eq(h.focused_workspace(), "w", "focused workspace")
    h.cmd("workspace q")  # from main: q is still on the side display
    h.eq(h.display_of("q").id, h.side.id, "display of q after switching from main")
    h.eq(h.shown_on(h.side.name), "q", "workspace on the side display")
    h.eq(h.shown_on(h.main.name), "w", "workspace on main")
    h.eq(h.focused_workspace(), "q", "focused workspace")
    h.eq(h.state()["workspaceDisplay"].get("q"), h.side.id, "workspaceDisplay[q] after the second switch")


@needs_displays(2)
def test_C4(h):
    """C4 workspace next/prev cycles through the workspaces of the focused display only."""
    h.cmd("workspace q1")  # ad hoc, created on main (focus is there); sorts between c and w
    h.cmd("workspace w")
    h.eq(sorted(w["name"] for w in h.workspaces() if w["display"] == h.main.name), ["c", "q1", "w"],
         "workspaces on main")
    for script, want in (("workspace next", "c"),  # w is the last one: wraps
                         ("workspace next", "q1"), ("workspace next", "w"),
                         ("workspace prev", "q1"), ("workspace prev", "c"), ("workspace prev", "w")):
        h.cmd(script)
        h.eq(h.focused_workspace(), want, "focused workspace after %r" % script)
        h.eq(h.shown_on(h.main.name), want, "workspace on main after %r" % script)
        h.eq(h.shown_on(h.side.name), "x", "workspace on the side display after %r" % script)


@needs_displays(2)
def test_C5(h):
    """C5 workspace-back-and-forth toggles between the last two workspaces; across displays focus follows."""
    h.cmd("workspace c")
    h.eq(h.focused_workspace(), "c", "after workspace c")
    h.cmd("workspace-back-and-forth")
    h.eq(h.focused_workspace(), "w", "first back-and-forth")
    h.cmd("workspace-back-and-forth")
    h.eq(h.focused_workspace(), "c", "second back-and-forth")
    h.cmd("workspace w")
    h.cmd("workspace s")  # the other display
    h.eq(h.focused_workspace(), "s", "after workspace s")
    h.cmd("workspace-back-and-forth")
    h.eq(h.focused_workspace(), "w", "back-and-forth across displays: focused workspace")
    h.eq(h.shown_on(h.main.name), "w", "workspace on main")
    h.eq(h.shown_on(h.side.name), "s", "workspace on the side display: unchanged")
    h.shown("ch")
    titles = {h.wins[n].title for n in ("aw", "aw2", "te")}
    h.wait_until(lambda: h.focused_window() in {(h.wins[n].pid, h.wins[n].title) for n in ("aw", "aw2", "te")},
                 4, "focus to return to a window of w on main (%s)" % sorted(titles))


def test_C6(h):
    """C6 An empty workspace parks every window of the old one and leaves focus alone."""
    front = h.front_pid()
    h.cmd("workspace q")  # an empty ad hoc workspace: an empty `c` would autostart the editor
    h.eq(h.focused_workspace(), "q", "focused workspace")
    h.eq(h.shown_on(h.main.name), "q", "workspace on main")
    for n in ("aw", "bw", "aw2", "te"):
        h.parked(n)
    h.eq(h.front_pid(), front, "frontmost app")  # Foci focused nothing
    h.eq(h.log_lines("launch"), [], "launches")


def test_C7(h):
    """C7 Switching to a workspace autostarts the project's missing apps there, but not autostart = false apps."""
    h.probes["ae"].close_window("alpha editor")
    h.wait_gone("alpha editor", "ae")
    h.settle()
    h.clear_log()
    h.cmd("workspace c")
    h.wait_until(lambda: h.log_lines("launch editor"), 8, "the editor launch")
    h.settle_os()  # no second launch
    h.eq(h.log_lines("launch editor"), ["launch editor alpha"], "editor launches")
    h.eq(h.log_lines("arg "), ["arg %s/src/alpha api" % os.environ.get("HOME", os.path.expanduser("~"))],
         "the {open} argument")
    adopt_probe(h, "le", "launch-editor-alpha")
    h.wait_window("alpha editor", "le", timeout=15)
    h.register("ae2", "le", "alpha editor")
    r = h.rec("ae2")
    h.eq((r["project"], r["workspace"]), ("alpha", "c"), "the launched window (project, workspace)")
    h.settle()
    h.shown("ae2")
    # beta uses web and term with autostart = false: empty shown workspaces launch nothing
    h.probes["pa"].close_window("beta - web")
    h.probes["bt"].close_window("beta term")
    h.wait_gone("beta - web", "pa")
    h.wait_gone("beta term", "bt")
    h.settle()
    h.cmd("workspace w")
    h.clear_log()
    h.cmd("project beta")  # w and x are shown, and beta has no web or term window
    h.settle_os()
    h.eq(h.project(), "beta", "project")
    h.eq([l for l in h.log_lines() if l.startswith("launch ")], [], "launches for autostart = false apps")


@needs_displays(2)
def test_C8(h):
    """C8 Parking geometry: a bottom corner, 1pt of width left, depending on the display arrangement."""
    h.cmd("workspace c")
    cases = [(n, h.main) for n in ("aw", "aw2", "bw", "te")] + [("bt", h.side)]
    for n, d in cases:
        h.parked(n)
        f = h.frame(n)
        want_x = parked_x(h, d, f.w)
        h.check(close(f.x, want_x), "%s is at x=%g, expected %g on %s" % (n, f.x, want_x, d.name))
        h.check(d.frame.maxy - h.TITLE_BAR - 3 <= f.y <= d.frame.maxy + 1,  # the window server pulls a title bar up
                "%s is at y=%g, expected the bottom edge of %s (%g)" % (n, f.y, d.name, d.frame.maxy))
        for o in h.displays():  # along any display's edge: at most a 1pt wide strip
            w = min(f.maxx, o.frame.maxx) - max(f.x, o.frame.x)
            vh = min(f.maxy, o.frame.maxy) - max(f.y, o.frame.y)
            h.check(vh <= 0 or w <= 1.01, "%s shows %gx%g pt on %s" % (n, w, vh, o.name))


@needs_displays(2)
def test_C9(h):
    """C9 list-workspaces: displays, shown and focused as in status, window counts of the active project."""

    def check_counts(counts):
        st = h.status()
        shown = {d["workspace"] for d in st["displays"]}
        windows = h.windows()
        for ws in h.workspaces():
            n = ws["name"]
            want = sum(1 for w in windows if w["workspace"] == n and not w["frozen"]
                       and w["project"] in (None, st["project"]))
            h.eq(ws["windows"], want, "windows of %s, from list-windows" % n)
            h.eq(ws["shown"], n in shown, "shown of %s" % n)
            h.eq(ws["focused"], n == st["focusedWorkspace"], "focused of %s" % n)
        for n, c in counts.items():
            h.eq(workspace_entry(h, n)["windows"], c, "windows of %s" % n)

    homes = {w["name"]: w["display"] for w in h.workspaces()}
    for n, d in (("w", h.main), ("c", h.main), ("x", h.side), ("s", h.side)):
        h.eq(homes.get(n), d.name, "display of %s" % n)
    check_counts({"w": 3, "c": 1, "x": 1, "s": 1})  # alpha: aw aw2 te / ae / at / ch
    h.cmd("project beta")
    check_counts({"w": 2, "c": 0, "x": 1, "s": 1})  # beta: bw te / - / bt / ch
    h.cmd("project alpha")
    h.cmd("workspace q")  # ad hoc, on main
    q = workspace_entry(h, "q")
    h.eq((q["display"], q["windows"], q["shown"], q["focused"]), (h.main.name, 0, True, True), "q")
    h.eq(workspace_entry(h, "w")["shown"], False, "w is no longer shown")
    check_counts({"w": 3, "q": 0})


@needs_displays(2)
@questionable("focus-display and move-to-display --follow change the focused workspace without setting "
              "previousWorkspace, so back-and-forth stays where it is")
def test_C10(h):
    """C10 previousWorkspace comes from workspace switches only: focus-display does not set it."""
    h.eq(h.state().get("previousWorkspace"), "x", "previousWorkspace after the reset")
    h.eq(other_display(h, h.main).id, h.side.id, "the display `focus-display next` reaches from main")
    h.cmd("focus-display next; workspace-back-and-forth")
    # spec says nothing else: the code leaves previousWorkspace at x, so the back-and-forth finds x focused already
    h.eq(h.focused_workspace(), "x", "focused workspace (stays on the other display instead of returning to w)")
    h.eq(h.state().get("previousWorkspace"), "x", "previousWorkspace")
    h.eq(h.shown_on(h.main.name), "w", "workspace on main")
    h.eq(h.shown_on(h.side.name), "x", "workspace on the side display")
    focused(h, "at")

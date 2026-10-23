"""H. Launch (Tests/E2E/SCENARIOS.md).

The launch templates of the test config write marker lines to $E2E_LOG and start a Probe with a control socket
named `launch-<app>-<project>` (`global-web` for the global launch).
"""
import os
import time

from harness import Fail, Probe, fixture, questionable


def _adopt(h, name, kind):
    return h.adopt_probe(name, kind)


def _wait_focused(h, name, timeout=6):
    h.wait_focused(name, timeout)


def _wait_frozen(h, name, value, timeout=10):
    h.wait_until(lambda: (h.wins[name].record or {}).get("frozen") is value, timeout,
                 "%s to have frozen=%s" % (name, value))


def _windows_of(h, title, project):
    return [w for w in h.windows() if w["title"] == title and w["project"] == project]


@fixture("aw", "aw2", "ae")
def test_H1(h):
    """H1 Focus an existing window: `launch web` shows `w` and focuses the project's web window, no launch."""
    h.cmd("workspace c")
    h.eq(h.focused_workspace(), "c", "focused workspace")
    h.shown("ae")
    h.clear_log()
    h.cmd("launch web")
    h.eq(h.focused_workspace(), "w", "focused workspace after launch web")
    # spec says focused(aw), code does aw2: Engine.newestWindow picks the highest seq of the project's `web` windows
    # (aw2 was created after aw).
    _wait_focused(h, "aw2")
    h.shown("aw2")
    h.eq(h.shown_on(h.display_of("w").name), "w", "workspace shown on w's display")
    h.settle_os()  # a launch, if any, would be logged by now
    h.eq(h.log_lines("launch"), [], "launches")
    h.eq(h.log_lines("global"), [], "global launches")


@fixture("aw", "bw", "aw2")
def test_H2(h):
    """H2 Launch for the project: `launch web` without an alpha web window runs the launch command once."""
    pa = h.probes["pa"]
    h.focus_terminal()  # closing the focused window would hand focus to bw, a hidden window: Foci would follow it
    for title in ("alpha - web", "alpha - web 2"):
        pa.close_window(title)
        h.wait_gone(title, "pa")
    h.settle()
    h.eq(_windows_of(h, "alpha - web", "alpha"), [], "alpha web windows")
    h.clear_log()
    # One script: nothing is synced in between, so the second launch sees no window and only the pending
    # launch (30 s) keeps it from running the command again.
    h.cmd("launch web; launch web")
    h.wait_until(lambda: h.log_lines("launch web"), 10, "the launch command to run")
    nw = _adopt(h, "launch-web-alpha", "a")
    h.wait_window("alpha - web", "launch-web-alpha", timeout=15)
    h.settle()
    h.register("nw", "launch-web-alpha", "alpha - web")
    h.eq(h.log_lines("launch web"), ["launch web alpha"], "launch log (FOCI_PROJECT=alpha)")
    r = h.rec("nw")
    h.eq((r["project"], r["workspace"], r["visible"]), ("alpha", "w", True), "new window (project, workspace, visible)")
    h.shown("nw")
    # Now there is a window: launch focuses it instead of launching again.
    h.cmd("launch web")
    _wait_focused(h, "nw")
    h.settle_os()
    h.eq(h.log_lines("launch web"), ["launch web alpha"], "launch log after a third launch web")
    h.check(nw.alive(), "the launched Probe is gone")


@fixture("aw", "bw")
def test_H3(h):
    """H3 Outside the project: `launch web` focuses the newest unlinked web window, else runs global-launch."""
    h.cmd("project --none")
    h.clear_log()
    h.cmd("launch web")  # no unlinked web window yet
    h.wait_until(lambda: h.log_lines("global web"), 10, "the global launch to run")
    _adopt(h, "global-web", "a")
    h.wait_window("personal - web", "global-web", timeout=15)
    h.settle()
    h.register("gw", "global-web", "personal - web")
    r = h.rec("gw")
    h.eq((r["project"], r["workspace"]), (None, "w"), "global window (project, workspace)")
    h.shown("gw")
    h.eq(h.log_lines("global web"), ["global web"], "global launches")
    h.eq(h.log_lines("launch"), [], "per-project launches")
    # An unlinked web window exists now: it gets the focus, nothing is launched.
    h.cmd("launch web")
    _wait_focused(h, "gw")
    h.settle_os()
    h.eq(h.log_lines("global web"), ["global web"], "global launches after the second launch web")
    # `term` has no global-launch.
    h.cmd("launch term", code=1, err="app 'term' has no global-launch command")
    h.settle_os()
    h.eq(h.log_lines("launch"), [], "per-project launches after launch term")


@fixture()
def test_H4(h):
    """H4 Unknown app: exit 1 `unknown app 'nope'`."""
    before = h.state()
    h.cmd("launch nope", code=1, err="unknown app 'nope'")
    h.eq(h.project(), "alpha", "project")
    h.eq(h.state(), before, "state.json")
    h.settle_os()
    h.eq(h.log_lines("launch"), [], "launches")
    h.eq(h.log_lines("global"), [], "global launches")


@fixture("aw", "ae")
def test_H5(h):
    """H5 {open} is quoted: the path of `open` reaches the launch command as one argument."""
    h.probes["ae"].quit()
    h.wait_gone("alpha editor")
    h.settle()
    h.clear_log()
    h.cmd("launch editor")
    h.wait_until(lambda: h.log_lines("arg "), 10, "the launch command to log its argument")
    _adopt(h, "launch-editor-alpha", "b")
    h.wait_window("alpha editor", "launch-editor-alpha", timeout=15)
    h.settle()
    h.eq(h.log_lines("launch editor"), ["launch editor alpha"], "launch log")
    h.eq(h.log_lines("arg "), ["arg " + os.path.expanduser("~/src/alpha api")], "argument lines ($HOME expanded)")
    h.register("ne", "launch-editor-alpha", "alpha editor")
    r = h.rec("ne")
    h.eq((r["project"], r["workspace"]), ("alpha", "c"), "new editor window (project, workspace)")


@fixture()
@questionable("a launch links the next unmatched window of the same app to the project, whatever its title")
def test_H6(h):
    """H6 A launch links the next unmatched window: within 30 s any unmatched `web` window joins the project."""
    h.eq(h.project(), "alpha", "project")
    t0 = time.time()
    h.cmd("launch web")
    h.wait_until(lambda: h.log_lines("launch web"), 10, "the launch command to run")
    _adopt(h, "launch-web-alpha", "a")
    h.wait_window("alpha - web", "launch-web-alpha", timeout=15)
    # An unmatched Probe A window from another process, as global-launch would start it.
    h.launch_probe("a", "pw", title="personal - web")
    h.wait_window("personal - web", "pw", timeout=15)
    h.settle()
    h.check(time.time() - t0 < 25, "too slow for the 30 s window of the pending launch (%gs)" % (time.time() - t0))
    h.register("pw", "pw", "personal - web")
    r = h.rec("pw")
    h.eq((r["project"], r["workspace"]), ("alpha", "w"), "personal - web (project, workspace)")
    # After 30 s the pending launch is gone (it is dropped at the next refresh): the next one stays unlinked.
    time.sleep(max(0.0, t0 + 32 - time.time()))
    h.launch_probe("a", "lw", title="late - web")
    h.wait_window("late - web", "lw", timeout=15)
    h.settle()
    h.register("lw", "lw", "late - web")
    r = h.rec("lw")
    h.eq((r["project"], r["workspace"]), (None, "w"), "late - web (project, workspace)")


@fixture("aw", "ae")
def test_H7(h):
    """H7 Minimized windows and autostart: a minimized editor still counts for autostart, not for `launch`."""
    h.probes["ae"].cmd("minimize", "alpha editor")
    _wait_frozen(h, "ae", True)
    h.settle()
    h.clear_log()
    h.cmd("workspace c")
    h.settle_os()  # a launch, if any, would be logged by now
    h.eq(h.log_lines("launch"), [], "launches after workspace c (the minimized window counts)")
    h.cmd("launch editor")
    h.wait_until(lambda: h.log_lines("launch editor"), 10, "the launch command to run")
    _adopt(h, "launch-editor-alpha", "b")
    h.wait_window("alpha editor", "launch-editor-alpha", timeout=15)
    h.settle()
    h.eq(h.log_lines("launch editor"), ["launch editor alpha"], "launch log")
    editors = _windows_of(h, "alpha editor", "alpha")
    h.eq(sorted(w["frozen"] for w in editors), [False, True], "frozen flags of the alpha editor windows")


@fixture("aw", "bw")
def test_H8(h):
    """H8 No global launch: `launch editor` while beta is active fails (beta has no editor, editor has no global)."""
    h.cmd("project beta")
    h.clear_log()
    h.cmd("launch editor", code=1, err="app 'editor' has no global-launch command")
    h.settle_os()
    h.eq(h.log_lines("launch"), [], "launches")
    h.eq(h.project(), "beta", "project")

"""B. Projects (Tests/E2E/SCENARIOS.md).

Same style as a_discovery.py. Private helpers at the top: they only use the harness API.
"""
import os
import time

from harness import Fail, Probe, Rect, fixture, needs_displays, questionable

BETA_MARK = "[[projects]]\nname = 'beta'"


# ---------------------------------------------------------------------- helpers


def _focus(h, name):
    h.focus_window(name)


def _focus_is(h, name):
    try:
        h.focused(name)
        return True
    except Fail:
        return False


def _wait_focused(h, name, timeout=6):
    h.wait_focused(name, timeout)


def _frames(h):
    return {n: h.frame(n) for n in h.wins}


def _records(h):
    out = {}
    for n in h.wins:
        r = h.rec(n)
        out[n] = (r["project"], r["workspace"], r["visible"])
    return out


def _project_names(h):
    return [p["name"] for p in h.projects()]


def _without_beta(text):
    """The test config minus the beta project (the last one of the file)."""
    i = text.index(BETA_MARK)
    if "[[projects]]" in text[i + len(BETA_MARK):]:
        raise Fail("beta is not the last project of the test config")
    return text[:i].rstrip("\n") + "\n"


def _set_config(h, text, names):
    """Writes the test config and waits for Foci to reload it (2 s timer): `list-projects` shows `names`."""
    h.write_config(text)
    h.wait_until(lambda: _project_names(h) == names, 12, "the config reload (projects %s)" % names)
    h.settle()


def _wait_project(h, name, timeout=8.0):
    h.wait_until(lambda: h.project() == name, timeout, "project %r" % name)


def _launch_lines(h):
    return [l for l in h.log_lines() if l.startswith("launch ") or l.startswith("arg ")]


def _columns(h, names, tol=2.0):
    """The windows are equal columns of `w`'s display, in this order (gap = 0)."""
    vis = h.display_of("w").visible
    w = vis.w / len(names)
    for i, n in enumerate(names):
        want = Rect(vis.x + i * w, vis.y, w, vis.h)
        f = h.frame(n)
        h.check(f.close_to(want, tol), "%s: frame %s, expected column %d of %d %s" % (n, f, i + 1, len(names), want))


def _workspace_layout(h, name):
    for w in h.workspaces():
        if w["name"] == name:
            return w["layout"]
    raise Fail("no workspace %r" % name)


def _close_ae(h):
    """Closes `ae` and waits until Foci has dropped it."""
    h.probes["ae"].close_window("alpha editor")
    h.wait_gone("alpha editor")
    h.settle_os()


def _attach_launched_editor(h, name="launch-editor-alpha"):
    """The Probe the editor launch template starts has the control socket `launch-editor-alpha`."""
    h.probes[name] = Probe(name, str(h.ctl / ("%s.sock" % name)), "b")
    h.wait_probe(name)
    h.probes[name].pid  # cached: the control socket may be gone once its last window is closed
    return h.probes[name]


# ---------------------------------------------------------------------- scenarios


@needs_displays(2)
def test_B1(h):
    """B1 Switch hides other projects on every display; unlinked windows stay."""
    h.cmd("project beta")
    h.eq(h.project(), "beta", "project")
    for n in ("bw", "bt", "te"):
        h.shown(n)
    for n in ("aw", "aw2", "at", "ae", "ch"):  # alpha's windows, and `ch` on `s`, which is not shown
        h.parked(n)
    h.maximized("bw")
    h.maximized("bt")
    h.eq(h.focused_workspace(), "w", "focused workspace")


def test_B2(h):
    """B2 No project: every linked window is parked, unlinked ones on shown workspaces stay."""
    h.cmd("project --none")
    h.eq(h.project(), None, "project")
    for n in ("aw", "aw2", "bw", "at", "bt", "ae"):
        h.parked(n)
    h.shown("te")
    h.parked("ch")  # unlinked, but `s` is not shown
    h.eq(h.focused_workspace(), "w", "focused workspace")


def test_B3(h):
    """B3 Cycle: next/prev wrap; from no project next is the first, prev the last."""
    for script, want in (("project next", "beta"), ("project next", "alpha"), ("project prev", "beta")):
        h.cmd(script)
        h.eq(h.project(), want, "project after %r" % script)
    h.cmd("project --none")
    h.cmd("project next")
    h.eq(h.project(), "alpha", "project after next from none")
    h.cmd("project --none")
    h.cmd("project prev")
    h.eq(h.project(), "beta", "project after prev from none")


def test_B4(h):
    """B4 Back and forth, including the 'none' project."""
    # After the reset the previous project is none.
    for script, want in (("project-back-and-forth", None), ("project-back-and-forth", "alpha")):
        h.cmd(script)
        h.eq(h.project(), want, "project after %r" % script)
    h.cmd("project beta")
    for script, want in (("project-back-and-forth", "alpha"), ("project-back-and-forth", "beta")):
        h.cmd(script)
        h.eq(h.project(), want, "project after %r" % script)
    h.cmd("project --none")  # the project before it is beta
    h.cmd("project-back-and-forth")
    h.eq(h.project(), "beta", "project after back-and-forth from none")
    h.cmd("project-back-and-forth")
    h.eq(h.project(), None, "project after back-and-forth again")


def test_B5(h):
    """B5 Unknown project: exit 1, the error on stderr, nothing moves, state unchanged."""
    st, state, frames, recs = h.status(), h.state(), _frames(h), _records(h)
    r = h.cmd("project nope", code=1, err="unknown project 'nope'")
    h.eq(r.err.strip(), "unknown project 'nope'", "stderr")
    h.eq(h.status(), st, "status")
    h.eq(h.state(), state, "state.json")
    h.eq(_records(h), recs, "(project, workspace, visible) of the windows")
    for n, f in frames.items():
        h.frame_unchanged(n, f)


def test_B6(h):
    """B6 Same project is a no-op for windows; focus is restored and a missing window of a shown workspace launches."""
    # Focus: the best window of the focused workspace (the last focused one, aw2) gets it back.
    _focus(h, "aw2")
    h.focus_terminal()
    frames, recs, prev = _frames(h), _records(h), h.state().get("previousProject")
    h.cmd("project alpha")
    _wait_focused(h, "aw2")
    h.eq(h.project(), "alpha", "project")
    h.eq(_records(h), recs, "(project, workspace, visible) of the windows")
    for n, f in frames.items():
        h.frame_unchanged(n, f)
    h.eq(h.state().get("previousProject"), prev, "previousProject")
    # Autostart: `c` is shown and alpha has no editor window.
    h.cmd("workspace c")
    h.shown("ae")
    _close_ae(h)
    h.clear_log()
    h.cmd("project alpha")
    h.wait_until(lambda: len(h.log_lines("launch ")) >= 1, 8, "the editor launch")
    h.settle_os()
    h.eq(_launch_lines(h)[0], "launch editor alpha", "first launch line")
    h.eq([l for l in _launch_lines(h) if l.startswith("launch ")], ["launch editor alpha"], "launches")
    h.eq(h.state().get("previousProject"), prev, "previousProject after the launch")


def test_B7(h):
    """B7 Focus is restored per project and workspace."""
    _focus(h, "aw2")
    h.cmd("project beta")
    _focus(h, "bw")
    h.cmd("project alpha")
    _wait_focused(h, "aw2")
    h.cmd("project beta")
    _wait_focused(h, "bw")


def test_B8(h):
    """B8 Focusing a hidden window follows it: its project and workspace come forward."""
    h.eq(h.project(), "alpha", "project before")
    h.probes["pa"].focus("beta - web")  # bw, parked
    _wait_project(h, "beta")
    h.settle()
    h.eq(h.focused_workspace(), "w", "focused workspace")
    h.shown("bw")
    _wait_focused(h, "bw")
    if h.side is None:
        return
    # The same for `bt`, which lives on the workspace of the other display.
    h.cmd("project alpha")
    h.eq(h.project(), "alpha", "project before the second focus")
    h.probes["bt"].focus("beta term")
    _wait_project(h, "beta")
    h.settle()
    h.eq(h.shown_on(h.side.name), "x", "workspace on the side display")
    h.eq(h.focused_workspace(), "x", "focused workspace")
    h.shown("bt")
    _wait_focused(h, "bt")


def test_B9(h):
    """B9 A stale focus at startup doesn't switch: the project and the focused workspace survive a restart."""
    h.cmd("project beta")
    _focus(h, "bw")
    h.cmd("workspace q")
    h.parked("bw")
    h.focused("bw")  # parked, but still the focused window
    h.restart_foci()
    h.settle_os()
    h.eq(h.project(), "beta", "project after the restart")
    h.eq(h.focused_workspace(), "q", "focused workspace after the restart")
    h.settle_os()
    h.eq(h.project(), "beta", "project a refresh later")
    h.eq(h.focused_workspace(), "q", "focused workspace a refresh later")
    h.parked("bw")


@fixture("aw", "ae")
def test_B10(h):
    """B10 Autostart on switch, on shown workspaces only; one launch with {open} as one argument; no repeat in 30 s."""
    _close_ae(h)
    h.clear_log()
    # Only `w` and `x` are shown: the editor lives on `c`, so nothing launches.
    h.cmd("project beta")
    h.cmd("project alpha")
    h.settle_os()
    h.eq(_launch_lines(h), [], "launches while `c` is not shown")
    # beta has no editor: `workspace c` launches nothing; the switch back to alpha does.
    h.cmd("project beta; workspace c")
    h.settle_os()
    h.eq(_launch_lines(h), [], "launches under beta")
    h.cmd("project alpha")
    h.wait_until(lambda: len(_launch_lines(h)) >= 2, 8, "the editor launch")
    t0 = time.time()
    h.settle_os()
    home = os.path.expanduser("~")
    h.eq(_launch_lines(h), ["launch editor alpha", "arg %s/src/alpha api" % home], "launch lines")
    # The new window is linked to alpha on `c`.
    p = _attach_launched_editor(h)
    r = h.wait_window("alpha editor")
    h.eq((r["project"], r["workspace"]), ("alpha", "c"), "launched window (project, workspace)")
    # Repeating the switch within 30 s doesn't launch again, even though the window is gone (pending launch).
    p.close_window("alpha editor")
    h.wait_gone("alpha editor")
    h.settle_os()
    h.check(time.time() - t0 < 25, "too slow: the 30 s of the pending launch are nearly over")
    h.cmd("project beta")
    h.cmd("project alpha")
    h.settle_os()
    h.eq(_launch_lines(h), ["launch editor alpha", "arg %s/src/alpha api" % home], "launch lines after the repeat")


@fixture("aw", "ae")
@questionable("relies on the A10 fallback: an unmatched Probe B window is an unlinked `editor` window on c, "
              "so the pending launch of editor decides its owner")
def test_B11(h):
    """B11 A window from a launch is linked by the pending launch (within 30 s)."""
    _close_ae(h)
    h.clear_log()
    h.cmd("launch editor")
    h.wait_until(lambda: len(h.log_lines("launch editor alpha")) >= 1, 8, "the editor launch")
    t0 = time.time()
    h.launch_probe("b", "o1", ["--group", "other"], title="other 1")
    h.register("o1", "o1", "other 1")
    h.wait_window("other 1", "o1")
    h.settle()
    h.eq((h.rec("o1")["project"], h.rec("o1")["workspace"]), ("alpha", "c"),
         "window started right after the launch (project, workspace)")
    # After 30 s the launch is not pending any more: the same kind of window stays unlinked.
    h.wait_until(lambda: time.time() >= t0 + 33, 45, "the pending launch to expire", interval=0.5)
    h.launch_probe("b", "o2", ["--group", "other"], title="other 2")
    h.register("o2", "o2", "other 2")
    h.wait_window("other 2", "o2")
    h.settle()
    h.eq((h.rec("o2")["project"], h.rec("o2")["workspace"]), (None, "c"),
         "window started 30 s after the launch (project, workspace)")
    h.eq(h.rec("o1")["project"], "alpha", "first window keeps its owner")


@fixture("aw", "bw", "at", "bt")
def test_B12(h):
    """B12 Project removed from config: its windows are unlinked and stay shown; adding it back re-links them."""
    orig = h.config_text
    try:
        # alpha active.
        _set_config(h, _without_beta(orig), ["alpha"])
        for n in ("bw", "bt"):
            r = h.rec(n)
            h.eq((r["project"], r["visible"]), (None, True), "%s after beta was removed (project, visible)" % n)
            h.shown(n)
        h.eq(h.project(), "alpha", "project")
        _set_config(h, orig, ["alpha", "beta"])
        for n in ("bw", "bt"):  # re-linked by the title and args rules
            h.wait_until(lambda n=n: h.rec(n)["project"] == "beta", 8, "%s to be linked to beta again" % n)
        h.settle()
        for n in ("bw", "bt"):
            h.parked(n)
        # beta active: no project once it is removed.
        h.cmd("project beta")
        _set_config(h, _without_beta(orig), ["alpha"])
        h.eq(h.project(), None, "project after the active project was removed")
        for n in ("bw", "bt"):
            h.eq(h.rec(n)["project"], None, "%s after beta was removed" % n)
            h.shown(n)
        _set_config(h, orig, ["alpha", "beta"])
        for n in ("bw", "bt"):
            h.wait_until(lambda n=n: h.rec(n)["project"] == "beta", 8, "%s to be linked to beta again" % n)
        h.eq(h.project(), None, "project after beta was added back")
    finally:
        _set_config(h, orig, ["alpha", "beta"])


def test_B13(h):
    """B13 Layout per project: tiles under alpha, maximized under beta; list-workspaces shows the active one's."""
    h.cmd("workspace w; layout tiles")
    _columns(h, ["aw", "aw2", "te"])
    h.eq(_workspace_layout(h, "w"), "tiles", "layout of w under alpha")
    h.cmd("project beta")
    h.maximized("bw")
    h.maximized("te")
    h.eq(_workspace_layout(h, "w"), "maximized", "layout of w under beta")
    h.cmd("project alpha")
    _columns(h, ["aw", "aw2", "te"])
    h.eq(_workspace_layout(h, "w"), "tiles", "layout of w under alpha again")


@fixture("aw", "aw2", "bw", "bt", "at")
def test_B14(h):
    """B14 Back and forth to a removed project fails; a manual link doesn't come back with the project."""
    orig = h.config_text
    try:
        h.cmd("project beta")
        h.cmd("project alpha")
        r = h.run_on("aw2", "link beta")
        h.eq(r.code, 0, "link beta exit code")
        h.settle()
        h.eq(h.rec("aw2")["project"], "beta", "aw2 after link beta")
        aw2_id = h.wins["aw2"].id
        h.eq(h.state()["windows"][str(aw2_id)]["manual"], True, "manual in state.json")
        h.parked("aw2")
        _set_config(h, _without_beta(orig), ["alpha"])
        h.eq(h.rec("aw2")["project"], None, "aw2 after beta was removed")
        h.shown("aw2")
        h.cmd("project-back-and-forth", code=1, err="unknown project 'beta'")
        h.eq(h.project(), "alpha", "project after the failed back-and-forth")
        _set_config(h, orig, ["alpha", "beta"])
        for n in ("bw", "bt"):  # rule-linked: re-linked
            h.wait_until(lambda n=n: h.rec(n)["project"] == "beta", 8, "%s to be linked to beta again" % n)
        h.settle_os()
        h.eq(h.rec("aw2")["project"], None, "aw2 after beta was added back")
        h.eq(h.state()["windows"][str(aw2_id)]["manual"], True, "manual after beta was added back")
        h.shown("aw2")
    finally:
        _set_config(h, orig, ["alpha", "beta"])


@fixture("aw", "bw")
def test_B15(h):
    """B15 Reload errors: a syntax error keeps the old config; a validation problem loads the new one."""
    orig = h.config_text
    try:
        # TOML syntax error: exit 1, `config: ...`, the old projects and apps stay.
        h.write_config(orig + "\n[[[ not toml\n")
        r = h.foci("reload-config")
        h.eq(r.code, 1, "exit code with a syntax error")
        h.check(r.err.startswith("config: "), "stderr does not start with 'config: ': %r" % r.err)
        h.eq(_project_names(h), ["alpha", "beta"], "projects after a syntax error")
        h.probes["pa"].new_window("beta - web 7")  # the `web` rule of the old config still links it
        h.wait_window("beta - web 7", "pa")
        h.register("nw", "pa", "beta - web 7")
        h.settle()
        h.eq(h.rec("nw")["project"], "beta", "new window after a syntax error")
        # Validation problem: a project that references an unknown app. The new config is in effect.
        bad = orig + "\n[[projects]]\nname = 'gamma'\napps = [{ app = 'ghost' }]\n"
        h.write_config(bad)
        r = h.foci("reload-config")
        h.eq(r.code, 1, "exit code with a validation problem")
        h.check("project 'gamma' references unknown app 'ghost'" in r.err, "stderr lacks the problem: %r" % r.err)
        h.eq(_project_names(h), ["alpha", "beta", "gamma"], "projects after a validation problem")
    finally:
        h.write_config(orig)
        h.foci("reload-config")
        h.wait_until(lambda: _project_names(h) == ["alpha", "beta"], 12, "the original config to be back")

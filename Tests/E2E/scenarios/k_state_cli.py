"""K. State, quit, CLI (Tests/E2E/SCENARIOS.md).

Persistence across Foci restarts, what quitting does to the windows, old state files, script/exit-code handling of
the `foci` CLI, `subscribe`, the URL router, `exec` and `mode`.
"""
import json
import shlex
import subprocess
import threading

from harness import Fail, Rect, fixture, needs_displays, questionable, run

ALL = ("aw", "bw", "aw2", "at", "bt", "ae", "ch", "te")


# ---------------------------------------------------------------------- private helpers


def _run_on(h, name, script):
    """`foci run --window <name> <script>`: expects exit 0, then settles."""
    r = h.run_on(name, script)
    h.eq(r.code, 0, "foci run --window %s %r: %s" % (name, script, r.err.strip()))
    h.settle()
    return r


def _wait_focused(h, name, timeout=6):
    h.wait_focused(name, timeout)


def _check_on_screen(h, workspace_of, display_of_ws):
    """After Foci quit: every window is fully reachable on the display of its workspace (no parked window).
    `workspace_of`: window name -> workspace; `display_of_ws`: workspace -> display name (both taken before)."""
    displays = {d.name: d for d in h.displays(refresh=True)}
    for n, ws in workspace_of.items():
        d = displays[display_of_ws[ws]]
        f = h.frame(n)
        cx, cy = f.center
        h.check(d.frame.contains(cx, cy), "%s is at %s, off its display %s %s" % (n, f, d.name, d.frame))
        h.check(f.overlap_area(d.frame) >= 0.5 * f.w * f.h, "%s at %s is mostly off %s %s" % (n, f, d.name, d.frame))


def _floating_frame(h, name):
    r = h.state()["windows"][str(h.wins[name].id)].get("floatingFrame")
    return r and Rect(r["x"], r["y"], r["width"], r["height"])


class _Subscriber:
    """`foci subscribe` in the background: `lines` collects its JSON status lines."""

    def __init__(self, h):
        self.proc = subprocess.Popen([h.foci_bin, "subscribe"], env=h.environment(), stdin=subprocess.DEVNULL,
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
        self.lines = []
        self._thread = threading.Thread(target=self._read, daemon=True)
        self._thread.start()

    def _read(self):
        for line in self.proc.stdout:
            self.lines.append(line.rstrip("\n"))

    def status(self, i=-1):
        return json.loads(self.lines[i])

    def close(self):
        if self.proc.poll() is None:
            self.proc.terminate()
        try:
            self.proc.wait(5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()


# ---------------------------------------------------------------------- K1 - K3


@needs_displays(2)
def test_K1(h):
    """K1 Persistence across restarts: owners, manual flags, layouts, weights, order, floating frames, displays."""
    vis = h.main.visible
    h.cmd("layout tiles")  # alpha|w in tiles
    _run_on(h, "aw2", "float")  # tiles are [aw, te]
    fx, fy, fw, fh = vis.x + 40, vis.y + 40, 600, 400
    h.drag("aw2", fx, fy, fw, fh)  # a floating frame of its own
    h.settle_os()
    dragged = Rect(fx, fy, fw, fh)
    h.check(_floating_frame(h, "aw2") is not None and _floating_frame(h, "aw2").close_to(dragged, 2),
            "floatingFrame of aw2 is %s, expected %s" % (_floating_frame(h, "aw2"), dragged))
    _run_on(h, "aw", "resize +200")  # weights
    seq_te = h.state()["windows"][str(h.wins["te"].id)]["seq"]
    _run_on(h, "aw", "move next")  # order: aw swaps with te
    _run_on(h, "ch", "link beta")  # a manual link
    h.cmd("focus-display next; workspace q; focus-display prev")  # an ad hoc workspace on the other display
    h.cmd("project beta")
    h.cmd("project alpha")  # previous project = beta
    h.settle_os()

    st = h.state()
    rec = {n: h.rec(n) for n in ALL}
    ids = {n: rec[n]["id"] for n in ALL}
    wins = {n: st["windows"][str(ids[n])] for n in ALL}
    h.check(wins["aw"]["weight"] > wins["te"]["weight"], "weights did not change: %s %s" % (wins["aw"], wins["te"]))
    h.eq(wins["aw"]["seq"], seq_te, "aw took the seq of te")
    h.eq(wins["ch"]["manual"], True, "ch manual")
    h.eq(wins["aw2"]["floating"], True, "aw2 floating")
    before_status = h.status()
    h.eq(before_status["project"], "alpha", "project before the restart")
    ws_display = {w["name"]: w["display"] for w in h.workspaces()}
    ws_of = {n: rec[n]["workspace"] for n in ALL}
    shown_before = {n: rec[n]["visible"] for n in ALL}
    frames_before = {n: h.frame(n) for n in ALL if shown_before[n]}
    h.check(shown_before["aw"] and not shown_before["at"], "setup: aw shown, at parked (x is not shown any more)")

    h.stop_foci()  # SIGTERM: restoreAll
    _check_on_screen(h, ws_of, ws_display)
    h.frame_unchanged("aw2", dragged, tol=2)  # floating windows at their frames
    h.start_foci()
    h.settle_os()

    after = h.state()
    for key in ("activeProject", "previousProject", "workspaceDisplay", "activeWorkspace", "focusedWorkspace",
                "layouts", "nextSeq"):
        h.eq(after.get(key), st.get(key), "state.json %s after the restart" % key)
    for n in ALL:
        a, b = after["windows"][str(ids[n])], wins[n]
        for field in ("owner", "workspace", "app", "floating", "manual", "seq", "weight"):
            h.eq(a.get(field), b.get(field), "%s %s after the restart" % (n, field))
    h.check(_floating_frame(h, "aw2").close_to(dragged, 2), "floatingFrame of aw2 is %s after the restart" %
            (_floating_frame(h, "aw2"),))
    h.eq(h.status(), before_status, "status after the restart")
    for n in ALL:
        r = h.rec(n)
        h.eq((r["project"], r["workspace"], r["visible"], r["floating"]),
             (rec[n]["project"], rec[n]["workspace"], rec[n]["visible"], rec[n]["floating"]),
             "%s (project, workspace, visible, floating) after the restart" % n)
        if shown_before[n]:
            h.shown(n)
        else:
            h.parked(n)  # parked again
    for n, f in frames_before.items():
        h.frame_unchanged(n, f, tol=2)


def test_K2(h):
    """K2 Quit restores windows: nothing stays parked, floating windows keep their frames."""
    vis = h.main.visible
    _run_on(h, "aw2", "float")
    fx, fy, fw, fh = vis.x + 60, vis.y + 60, 500, 350
    h.drag("aw2", fx, fy, fw, fh)
    h.settle_os()  # Foci remembers the dragged frame
    for n in ("bw", "bt", "ae", "ch"):
        h.parked(n)  # setup: these are parked right now
    ws_of = {n: h.rec(n)["workspace"] for n in ALL}
    ws_display = {w["name"]: w["display"] for w in h.workspaces()}
    try:
        h.stop_foci()  # `pkill -TERM -x foci` for the Foci under test
        _check_on_screen(h, ws_of, ws_display)
        h.frame_unchanged("aw2", Rect(fx, fy, fw, fh), tol=2)
        for n in ("bw", "bt", "ae", "ch"):
            f = h.frame(n)
            h.check(f.w > 50 and f.h > 50, "%s was restored with a silly size %s" % (n, f))
    finally:
        try:
            h.start_foci()
        except Exception:  # noqa: BLE001 - the next scenario starts from a fresh Foci anyway
            pass


@fixture("aw", "bw", "at", "ch")
@questionable("a state file without nextSeq restarts the counter at 0: new windows get seq values that collide "
              "with the old windows'; their order falls back to the window ID")
def test_K3(h):
    """K3 Old state files: missing layouts, seq, weight, displayHistory, nextSeq load with defaults."""
    names = ["aw", "bw", "at", "ch"]
    h.cmd("layout tiles")  # a runtime layout, in `layouts`
    h.eq({w["name"]: w["layout"] for w in h.workspaces()}["w"], "tiles", "layout of w before")
    h.settle_os()
    ids = {n: h.wins[n].id for n in names}
    old = h.state()
    h.check(old.get("layouts"), "setup: state.json has no layouts")
    seq_kept = {n: old["windows"][str(ids[n])]["seq"] for n in ("aw", "bw")}

    h.stop_foci()
    path = h.home / "state.json"
    data = json.loads(path.read_text())
    for key in ("layouts", "nextSeq", "displayHistory"):
        data.pop(key, None)
    for r in data["windows"].values():
        r.pop("weight", None)
    for n in ("at", "ch"):  # no seq: the default is 0; aw and bw keep theirs
        data["windows"][str(ids[n])].pop("seq", None)
    path.write_text(json.dumps(data))
    h.start_foci()
    h.settle_os()

    h.check_fixture(names)  # owners and workspaces from the file
    h.eq(h.project(), "alpha", "active project")
    h.eq({w["name"]: w["layout"] for w in h.workspaces()}["w"], "maximized", "layout of w: the default")
    h.wait_until(lambda: h.state().get("displayHistory"), 8, "displayHistory to be rebuilt")
    now = h.state()
    for n in names:
        h.eq(now["windows"][str(ids[n])]["weight"], 1, "weight of %s" % n)
    h.eq([now["windows"][str(ids[n])]["seq"] for n in ("at", "ch")], [0, 0], "seq without a seq key")
    h.eq({n: now["windows"][str(ids[n])]["seq"] for n in ("aw", "bw")}, seq_kept, "seq of the windows that kept it")

    # Known: nextSeq restarts at 0, so a new window collides with the old windows that have seq 0.
    # (the spec and the code agree: nextSeq defaults to 0 when the key is missing)
    h.probes["pa"].new_window("alpha - web 2")
    h.register("aw2", "pa", "alpha - web 2")
    h.wait_window("alpha - web 2", "pa")
    h.settle()
    seq_new = h.state()["windows"][str(h.wins["aw2"].id)]["seq"]
    h.eq(seq_new, 0, "seq of a new window after the counter restarted")
    same = [n for n in names if h.state()["windows"][str(ids[n])]["seq"] == seq_new]
    h.check(same, "the new window's seq %d collides with no old window" % seq_new)


# ---------------------------------------------------------------------- K4 - K8


def test_K4(h):
    """K4 Scripts and exit codes: scripts run in order; a failing command gives exit 1, usage 2, no app 3."""
    main = h.main.name
    h.cmd("workspace c; layout tiles; workspace w")
    layouts = {w["name"]: w["layout"] for w in h.workspaces()}
    h.eq((layouts["c"], layouts["w"]), ("tiles", "maximized"), "layouts of c and w: `layout` ran while c was focused")
    h.eq(h.focused_workspace(), "w", "focused workspace after the script")
    h.eq(h.shown_on(main), "w", "workspace on main after the script")

    # A failing command doesn't stop the script: `workspace c` still runs.
    r = h.cmd("project nope; workspace c", code=1, err="unknown project 'nope'")
    h.eq(r.out, "", "stdout")
    h.eq(h.shown_on(main), "c", "workspace c is shown after the failed script")
    h.eq(h.focused_workspace(), "c", "focused workspace after the failed script")
    h.eq(h.project(), "alpha", "project after the failed script")

    r = h.foci("bogus")
    h.eq(r.code, 2, "foci bogus exit code")
    h.check("unknown command 'bogus'" in r.err, "stderr of foci bogus: %r" % r.err)

    # Exit 2 is decided by the client, before it looks for the app; exit 3 means that no app answers.
    empty = h.e2e / "empty"
    empty.mkdir(parents=True, exist_ok=True)
    env = dict(h.environment(), FOCI_HOME=str(empty))
    p = run([h.foci_bin, "bogus"], env=env)
    h.eq(p.returncode, 2, "foci bogus without a running app")
    p = run([h.foci_bin, "status"], env=env)
    h.eq(p.returncode, 3, "foci status without a running app")
    h.check("not running" in p.stderr, "stderr without an app: %r" % p.stderr)
    p = run([h.foci_bin, "workspace", "c"], env=env)
    h.eq(p.returncode, 3, "foci workspace c without a running app")


@fixture("aw", "bw")
def test_K5(h):
    """K5 Subscribe: one status line per project/workspace/display change, none for no-ops."""
    sub = _Subscriber(h)
    try:
        h.wait_until(lambda: len(sub.lines) >= 1, 5, "the first status line")
        first = sub.status(0)
        h.eq((first["project"], first["focusedWorkspace"], first["mode"]), ("alpha", "w", "main"), "first line")
        n = len(sub.lines)

        def expect_new(script, check):
            nonlocal n
            h.cmd(script)
            h.wait_until(lambda: len(sub.lines) >= n + 1, 4, "a status line after %r" % script)
            h.settle_os()  # no more lines come
            h.eq(len(sub.lines), n + 1, "status lines after %r" % script)
            n += 1
            check(sub.status())

        def expect_none(script, code=0):
            h.cmd(script, code=code)
            h.settle_os()
            h.eq(len(sub.lines), n, "status lines after the no-op %r" % script)

        # q: an ad hoc workspace on main, empty, so nothing autostarts.
        expect_new("workspace q", lambda s: h.eq(s["focusedWorkspace"], "q", "focusedWorkspace"))
        expect_new("project beta", lambda s: h.eq(s.get("project"), "beta", "project"))
        expect_none("project beta")  # B6: same project
        expect_none("workspace q")  # same workspace
        expect_none("mode main")
        if len(h.displays()) > 1:
            expect_new("focus-display next", lambda s: h.check(s["focusedWorkspace"] != "q", "focus did not move"))
            expect_new("focus-display prev", lambda s: h.eq(s["focusedWorkspace"], "q", "focusedWorkspace"))
        else:
            expect_none("focus-display next")  # D5: one display, nothing to move to
        expect_new("project --none", lambda s: h.eq(s.get("project"), None, "project"))
    finally:
        sub.close()


def test_K6(h):
    """K6 URL router: `foci open` from a Probe window's process switches to the opener's project."""
    foci = "FOCI_HOME=%s %s open https://x" % (shlex.quote(str(h.home)), shlex.quote(h.foci_bin))
    main = h.main.name

    # bt is a beta window: focusing it follows it to beta (B8). The router then sends the link to beta's web app.
    h.probes["bt"].focus("beta term")
    h.wait_until(lambda: h.project() == "beta", 8, "the project to follow bt")
    h.settle()
    _wait_focused(h, "bt")
    h.clear_log()
    h.eq(h.probes["bt"].cmd("spawn", foci), "0", "exit code of `foci open` run from bt's process")
    h.wait_until(lambda: "open-url https://x beta" in h.log_lines(), 8, "the open-url launch for beta")
    h.settle()
    h.eq(len([l for l in h.log_lines() if l.startswith("open-url")]), 1, "open-url launches")
    h.eq(h.project(), "beta", "project after foci open")
    h.eq(h.shown_on(main), "w", "workspace on main")
    h.shown("bw")
    _wait_focused(h, "bw")

    # The opener decides, not the focus: with alpha active again, a link from bt's process still goes to beta.
    h.cmd("project alpha")
    h.clear_log()
    h.eq(h.probes["bt"].cmd("spawn", foci), "0", "exit code of the second `foci open`")
    h.wait_until(lambda: "open-url https://x beta" in h.log_lines(), 8, "the second open-url launch for beta")
    h.settle()
    h.eq(h.project(), "beta", "project after the second foci open")
    _wait_focused(h, "bw")

    # ch is unlinked: the link goes to the active project's web window.
    h.cmd("project alpha")
    h.clear_log()
    h.eq(h.probes["ch"].cmd("spawn", foci), "0", "exit code of `foci open` run from ch's process")
    h.wait_until(lambda: "open-url https://x alpha" in h.log_lines(), 8, "the open-url launch for alpha")
    h.settle()
    h.eq(h.project(), "alpha", "project after foci open from an unlinked window")
    pa = h.probes["pa"].pid
    h.wait_until(lambda: h.focused_window()[0] == pa and h.focused_window()[1] in ("alpha - web", "alpha - web 2"),
                 6, "an alpha web window to be focused")


@fixture()
def test_K7(h):
    """K7 exec: the rest of the script is the command, `;` included, with FOCI_PROJECT set."""
    show = "printf 'exec %s\\n' \"$FOCI_PROJECT\" >> \"$E2E_LOG\""

    def lines():
        return [l for l in h.log_lines() if l.startswith("exec") or l == "second"]

    def wait_for(expected):
        h.wait_until(lambda: lines() == expected, 10, "the log to be %r (is %r)" % (expected, lines()))

    h.eq(h.project(), "alpha", "project")
    h.cmd("exec " + show)
    wait_for(["exec alpha"])
    h.cmd("exec " + show + "; printf 'second\\n' >> \"$E2E_LOG\"")  # one command, not two scripts
    wait_for(["exec alpha", "exec alpha", "second"])
    h.cmd("project --none")
    h.cmd("exec " + show)
    wait_for(["exec alpha", "exec alpha", "second", "exec "])  # empty without a project
    h.cmd("project beta; exec " + show)  # the project switch happens first
    wait_for(["exec alpha", "exec alpha", "second", "exec ", "exec beta"])


@fixture()
def test_K8(h):
    """K8 Modes: `mode main` is fine, an unknown mode is an error, the mode stays main."""
    h.eq(h.status()["mode"], "main", "mode at the start")
    r = h.foci("mode", "main")
    h.eq((r.code, r.err), (0, ""), "foci mode main")
    r = h.foci("mode", "nope")
    h.eq(r.code, 1, "foci mode nope exit code")
    h.check("unknown mode 'nope'" in r.err, "stderr of foci mode nope: %r" % r.err)
    h.eq(h.status()["mode"], "main", "mode after the unknown one")
    h.eq(h.foci("status", "--json", json_out=True).out["mode"], "main", "mode in status --json")

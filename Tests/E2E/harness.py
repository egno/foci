"""Harness of the Foci end-to-end suite: lifecycle, helpers and assertions. Python 3.9, standard library only.

Scenarios (Tests/E2E/scenarios/*.py) get a `Harness` as `h`. See Tests/E2E/SCENARIOS.md for the spec and the
bottom half of this module for the decorators that mark scenarios.
"""
import collections
import json
import os
import re
import shlex
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DEFAULT_E2E_DIR = (
    "/private/tmp/claude-501/-Users-av-proj-foci/76ce98d3-b1b6-4af6-a101-7fdbd998758d/scratchpad/e2e"
)
USER_APP = os.path.expanduser("~/Applications/Foci.app")
TEXTEDIT_FILE = "te.txt"

Result = collections.namedtuple("Result", "code out err")


class Fail(AssertionError):
    """A scenario expectation failed."""


class SetupError(RuntimeError):
    """The environment can't run the suite (build failed, no Accessibility permission, ...)."""


class FatalError(SetupError):
    """Foci itself won't start: no scenario can run."""


def short_path(p):
    """/private/tmp is /tmp: the short spelling keeps Unix socket paths below the 104 byte limit."""
    p = str(p)
    return p[len("/private"):] if p.startswith("/private/tmp/") else p


def close(a, b, tol=1.0):
    return abs(a - b) <= tol


class Rect(collections.namedtuple("Rect", "x y w h")):
    """Accessibility coordinates: origin top-left of the main display, y down."""

    @property
    def maxx(self):
        return self.x + self.w

    @property
    def maxy(self):
        return self.y + self.h

    @property
    def center(self):
        return (self.x + self.w / 2, self.y + self.h / 2)

    def contains(self, px, py):
        return self.x <= px < self.maxx and self.y <= py < self.maxy

    def inset(self, d):
        return Rect(self.x + d, self.y + d, self.w - 2 * d, self.h - 2 * d)

    def close_to(self, other, tol=1.0):
        return all(close(a, b, tol) for a, b in zip(self, other))

    def overlap_area(self, other):
        w = min(self.maxx, other.maxx) - max(self.x, other.x)
        h = min(self.maxy, other.maxy) - max(self.y, other.y)
        return max(w, 0) * max(h, 0)

    def __str__(self):
        return "(%g,%g %gx%g)" % self


class Display(collections.namedtuple("Display", "id name main frame visible")):
    """`frame` and `visible` (without menu bar and Dock) are `Rect`s in Accessibility coordinates."""


def run(cmd, **kw):
    kw.setdefault("capture_output", True)
    kw.setdefault("text", True)
    return subprocess.run(cmd, **kw)


def osascript(script, lang=None, timeout=20):
    cmd = ["osascript"] + (["-l", lang] if lang else []) + ["-e", script]
    p = run(cmd, timeout=timeout)
    if p.returncode != 0:
        raise RuntimeError("osascript failed: %s" % p.stderr.strip())
    return (p.stdout or p.stderr).strip()


JXA_DISPLAYS = """
ObjC.import('AppKit');
$.NSApplication.sharedApplication;  // without it visibleFrame ignores the menu bar of secondary displays
var s = $.NSScreen.screens, out = [], ph = s.objectAtIndex(0).frame.size.height;
function ax(r) { return [r.origin.x, ph - (r.origin.y + r.size.height), r.size.width, r.size.height]; }
for (var i = 0; i < s.count; i++) {
  var sc = s.objectAtIndex(i);
  out.push({id: ObjC.unwrap(sc.deviceDescription.objectForKey('NSScreenNumber')),
            name: ObjC.unwrap(sc.localizedName), frame: ax(sc.frame), visible: ax(sc.visibleFrame)});
}
JSON.stringify(out)
"""

JXA_REGULAR_APPS = """
ObjC.import('AppKit');
var a = $.NSWorkspace.sharedWorkspace.runningApplications, out = [];
for (var i = 0; i < a.count; i++) {
  var x = a.objectAtIndex(i);
  if (x.activationPolicy == 0 && x.bundleIdentifier.js) out.push(x.bundleIdentifier.js);
}
JSON.stringify(out)
"""


def displays_now():
    """All displays, main first (NSScreen order). Not cached: displays can change under a running suite."""
    out = []
    for d in json.loads(osascript(JXA_DISPLAYS, "JavaScript")):
        out.append(Display(int(d["id"]), d["name"], not out, Rect(*d["frame"]), Rect(*d["visible"])))
    return out


def terminal_bundle_id():
    """The app the runner runs in: it must not be managed by the Foci under test."""
    if os.environ.get("E2E_TERMINAL"):
        return os.environ["E2E_TERMINAL"]
    if os.environ.get("__CFBundleIdentifier"):
        return os.environ["__CFBundleIdentifier"]
    pid = os.getpid()
    for _ in range(32):
        p = run(["ps", "-o", "ppid=", "-p", str(pid)])
        pid = int(p.stdout.strip() or 0)
        if pid <= 1:
            break
        asn = run(["lsappinfo", "find", "pid=%d" % pid]).stdout.strip()
        if asn:
            m = re.search(r'bundleID="([^"]+)"', run(["lsappinfo", "info", "-only", "bundleid", asn]).stdout)
            if m:
                return m.group(1)
    raise SetupError("can't tell the terminal's bundle ID: set E2E_TERMINAL")


# Fixture windows: name -> (process, title). `te` is a TextEdit document, the rest are Probe windows.
# A process starts with its first window and gets the rest through `new-window`, in this order.
FIXTURE_WINDOWS = collections.OrderedDict([
    ("aw", ("pa", "alpha - web")),
    ("bw", ("pa", "beta - web")),
    ("aw2", ("pa", "alpha - web 2")),
    ("at", ("at", "alpha term")),
    ("bt", ("bt", "beta term")),
    ("ae", ("ae", "alpha editor")),
    ("ch", ("ch", "chat")),
    ("te", ("te", TEXTEDIT_FILE)),
])
# Probe processes of the fixture: name -> (bundle kind, extra args).
FIXTURE_PROCESSES = {
    "pa": ("a", []),
    "at": ("b", ["--group", "alpha"]),
    "bt": ("b", ["--group", "beta"]),
    "ae": ("b", ["--group", "alpha-edit"]),
    "ch": ("b", ["--group", "chat"]),
}
# What the rules must make of the fixture windows: name -> (owner, workspace).
FIXTURE_EXPECT = {
    "aw": ("alpha", "w"), "bw": ("beta", "w"), "aw2": ("alpha", "w"), "at": ("alpha", "x"),
    "bt": ("beta", "x"), "ae": ("alpha", "c"), "ch": (None, "s"), "te": (None, "w"),
}

CONFIG_TEMPLATE = r"""
gap = 0
accordion-padding = 0  # maximized = full size; see SCENARIOS.md F13

[workspaces]
w = 'main'
c = 'main'
x = 'secondary'
s = 'secondary'

[apps.runner]
bundle-id = '@TERMINAL@'
manage = false

[apps.web]                      # one process, windows linked by title
bundle-id = 'dev.foci.probe.a'
title = '^{project} - web'
workspace = 'w'
launch = '''printf 'launch web %s\n' "$FOCI_PROJECT" >> "$E2E_LOG"; open -gna "$E2E_DIR/apps/Probe A.app" --args --title "{project} - web" --ctl launch-web-{project}'''
global-launch = '''printf 'global web\n' >> "$E2E_LOG"; open -gna "$E2E_DIR/apps/Probe A.app" --args --title "personal - web" --ctl global-web'''
open-url = '''printf 'open-url %s %s\n' {url} {project} >> "$E2E_LOG"'''

[apps.term]                     # one process per project, linked by args
bundle-id = 'dev.foci.probe.b'
args = '--group {project}( |$)'
workspace = 'x'
launch = '''printf 'launch term %s\n' "$FOCI_PROJECT" >> "$E2E_LOG"; open -gna "$E2E_DIR/apps/Probe B.app" --args --group {project} --title "{project} term" --ctl launch-term-{project}'''

[apps.editor]
bundle-id = 'dev.foci.probe.b'
args = '--group {project}-edit( |$)'
workspace = 'c'
launch = '''printf 'launch editor %s\n' "$FOCI_PROJECT" >> "$E2E_LOG"; printf 'arg %s\n' {open} >> "$E2E_LOG"; open -gna "$E2E_DIR/apps/Probe B.app" --args --group {project}-edit --title "{project} editor" --ctl launch-editor-{project}'''

[apps.chat]                     # unlinked app with a home workspace
bundle-id = 'dev.foci.probe.b'
args = '--group chat( |$)'
workspace = 's'

[apps.dialog]
bundle-id = 'dev.foci.probe.b'
args = '--group dialog( |$)'
floating = true

[apps.ignored]
bundle-id = 'dev.foci.probe.b'
args = '--group ignored( |$)'
manage = false

[apps.notes]                    # its own bundle; new windows join the active project if it uses notes
bundle-id = 'dev.foci.probe.c'
title = '^{project} notes$'
new-windows = 'active-project'

[[projects]]
name = 'alpha'
apps = [
  { app = 'web', autostart = false },
  { app = 'term', autostart = false },
  { app = 'editor', open = ['~/src/alpha api'] },
  { app = 'notes', autostart = false },
]

[[projects]]
name = 'beta'
apps = [{ app = 'web', autostart = false }, { app = 'term', autostart = false }]
"""


class ProbeError(Exception):
    pass


class Probe:
    """A running Probe process and its control socket."""

    def __init__(self, name, path, kind="?"):
        self.name = name
        self.path = path
        self.kind = kind
        self._pid = None

    def raw(self, line, timeout=20):
        """One command line, the reply line (`ok ...` or `err ...`)."""
        s = socket.socket(socket.AF_UNIX)
        s.settimeout(timeout)
        try:
            if len(self.path) < 104:
                s.connect(self.path)
            else:  # the sockaddr limit: connect by a relative name from the socket's directory
                cwd = os.getcwd()
                os.chdir(os.path.dirname(self.path))
                try:
                    s.connect(os.path.basename(self.path))
                finally:
                    os.chdir(cwd)
            s.sendall((line + "\n").encode())
            buf = b""
            while not buf.endswith(b"\n"):
                chunk = s.recv(65536)
                if not chunk:
                    break
                buf += chunk
        finally:
            s.close()
        return buf.decode().strip()

    def cmd(self, *args, timeout=20):
        """`probe.cmd('rename', 'a', 'b')`: arguments are quoted. Returns the text after `ok`; raises on `err`.
        `spawn` takes one string, the shell command."""
        if args and args[0] == "spawn":
            line = "spawn " + " ".join(args[1:])
        else:
            line = " ".join(shlex.quote(str(a)) for a in args)
        reply = self.raw(line, timeout)
        if reply == "ok" or reply.startswith("ok "):
            return reply[3:]
        raise ProbeError("%s: %s -> %s" % (self.name, line, reply))

    @property
    def pid(self):
        if self._pid is None:
            self._pid = int(self.cmd("pid"))
        return self._pid

    def alive(self):
        try:
            return self.raw("ping", 2) == "ok"
        except (OSError, socket.timeout):
            return False

    def frame(self, title):
        return Rect(*[float(v) for v in self.cmd("frame", title).split()])

    def windows(self):
        """[{id, title, minimized, fullscreen, frame}] of the windows the probe owns."""
        return json.loads(self.cmd("list"))

    def state(self):
        """{pid, frontmost, active, hidden, key}: `key` is the title of the key window."""
        return json.loads(self.cmd("state"))

    def new_window(self, title):
        return int(self.cmd("new-window", title))

    def close_window(self, title):
        self.cmd("close", title)

    def rename(self, old, new):
        self.cmd("rename", old, new)

    def focus(self, title):
        self.cmd("focus", title)

    def move(self, title, x, y, w, h):
        self.cmd("move", title, x, y, w, h)

    def quit(self):
        try:
            self.cmd("quit", timeout=3)
        except (OSError, socket.timeout, ProbeError):
            pass


class Win:
    """A fixture window by name. Its Foci window ID is looked up on demand (it changes when the app restarts)."""

    def __init__(self, h, name, proc, title):
        self.h, self.name, self.proc, self.title = h, name, proc, title

    @property
    def pid(self):
        if self.proc == "te":
            return self.h.textedit_pid()
        return self.h.probes[self.proc].pid

    @property
    def record(self):
        """The window as `foci list-windows --json` shows it, or None."""
        for w in self.h.windows():
            if w["pid"] == self.pid and w["title"] == self.title:
                return w
        return None

    @property
    def id(self):
        r = self.record
        if r is None:
            raise Fail("window %s (%r) is not in list-windows" % (self.name, self.title))
        return r["id"]


class Harness:
    def __init__(self, e2e_dir=None, build=True, verbose=False):
        self.e2e = Path(short_path(e2e_dir or os.environ.get("E2E_DIR") or DEFAULT_E2E_DIR))
        self.home = self.e2e / "home"
        self.apps = self.e2e / "apps"
        self.ctl = self.e2e / "ctl"
        self.log_path = self.e2e / "e2e.log"
        self.foci_log = self.e2e / "foci.log"
        self.foci_bin = str(REPO / "build/Foci.app/Contents/MacOS/foci")
        self.build = build
        self.verbose = verbose
        self.probes = {}
        self.wins = {}  # fixture windows started so far: name -> Win
        self.foci_proc = None
        self.user_foci_was_running = False
        self.unsettled = 0  # settle() calls that timed out in the current scenario
        self.config_text = None
        self._displays = None
        self._textedit_pid = None
        self._foreign = []
        self._terminal = None

    # ------------------------------------------------------------------ lifecycle

    def say(self, msg):
        if self.verbose:
            print("  [e2e] " + msg, flush=True)

    def setup(self):
        """Stops the user's Foci, builds, writes the test config and starts Foci with FOCI_HOME."""
        if len(str(self.home / "foci.sock")) >= 104:
            raise SetupError("E2E_DIR is too long for Foci's Unix socket (104 bytes): %s" % self.e2e)
        self._terminal = terminal_bundle_id()
        if run(["pgrep", "-x", "TextEdit"]).returncode == 0 and not os.environ.get("E2E_KILL_TEXTEDIT"):
            raise SetupError("TextEdit is running: the suite closes its windows. Quit it, or set E2E_KILL_TEXTEDIT=1")
        self.user_foci_was_running = run(["pgrep", "-x", "foci"]).returncode == 0
        self.stop_user_foci()
        self.e2e.mkdir(parents=True, exist_ok=True)
        if self.build:
            self.build_all()
        elif not os.path.exists(self.foci_bin) or not (self.apps / "Probe A.app").exists():
            raise SetupError("--no-build needs build/Foci.app and %s/apps built before" % self.e2e)
        self._foreign = json.loads(osascript(JXA_REGULAR_APPS, "JavaScript"))
        self.say("terminal %s, unmanaged apps %s" % (self._terminal, self._foreign))

    def stop_user_foci(self):
        if run(["pgrep", "-x", "foci"]).returncode != 0:
            return
        run(["pkill", "-TERM", "-x", "foci"])  # quitting restores the parked windows
        self.wait_until(lambda: run(["pgrep", "-x", "foci"]).returncode != 0, 10, "Foci to quit",
                        error=SetupError)

    def build_all(self):
        self.say("make app")
        p = run(["make", "app"], cwd=str(REPO))
        if p.returncode != 0:
            raise SetupError("make app failed:\n" + (p.stdout + p.stderr)[-3000:])
        self.say("building Probe")
        env = dict(os.environ, E2E_DIR=str(self.e2e))
        p = run([str(REPO / "Tests/E2E/Probe/build.sh")], env=env)
        if p.returncode != 0:
            raise SetupError("Probe build failed:\n" + (p.stdout + p.stderr)[-3000:])

    def teardown(self):
        """Stops the Foci under test and the fixture, then brings the user's Foci back. Never raises."""
        for step in (self.stop_foci, self.kill_fixture, self.restart_user_foci):
            try:
                step()
            except BaseException as e:  # noqa: BLE001 - cleanup must go on
                print("teardown: %s: %s" % (step.__name__, e), file=sys.stderr)

    def restart_user_foci(self):
        if self.user_foci_was_running:
            run(["open", USER_APP])
            self.user_foci_was_running = False

    # ------------------------------------------------------------------ Foci process

    def environment(self):
        env = dict(os.environ)
        env.update(FOCI_HOME=str(self.home), E2E_DIR=str(self.e2e), E2E_LOG=str(self.log_path))
        return env

    def start_foci(self):
        self.home.mkdir(parents=True, exist_ok=True)
        out = open(self.foci_log, "ab")
        self.foci_proc = subprocess.Popen(
            [self.foci_bin], env=self.environment(), stdin=subprocess.DEVNULL, stdout=out, stderr=out,
            start_new_session=True)
        deadline = time.time() + 20
        last = None
        while time.time() < deadline:
            if self.foci_proc.poll() is not None:
                raise FatalError("Foci exited with %s, see %s" % (self.foci_proc.returncode, self.foci_log))
            last = self.foci("status")
            if last.code == 0:
                return
            time.sleep(0.2)
        raise FatalError(
            "Foci did not answer in 20 s (%s). Does build/Foci.app have the Accessibility permission? "
            "See %s" % ((last.err or "").strip(), self.foci_log))

    def stop_foci(self, wait=8):
        """SIGTERM: Foci puts every window back on screen before it exits."""
        p, self.foci_proc = self.foci_proc, None
        if p is None or p.poll() is not None:
            return
        p.send_signal(signal.SIGTERM)
        try:
            p.wait(wait)
        except subprocess.TimeoutExpired:
            p.kill()
            p.wait()

    def restart_foci(self, kill=False):
        """For persistence scenarios: the same home, so config and state stay."""
        if kill and self.foci_proc:
            self.foci_proc.kill()
            self.foci_proc.wait()
            self.foci_proc = None
        self.stop_foci()
        self.start_foci()

    # ------------------------------------------------------------------ CLI

    def foci(self, *args, json_out=False, timeout=20):
        """Runs `foci <args>` against the app under test. Returns `Result(code, out, err)`;
        with `json_out` `out` is the parsed JSON (None if the command failed)."""
        p = run([self.foci_bin] + [str(a) for a in args], env=self.environment(), timeout=timeout)
        out = p.stdout
        if json_out:
            try:
                out = json.loads(p.stdout)
            except ValueError:
                out = None
        return Result(p.returncode, out, p.stderr)

    def cmd(self, script, code=0, err=None, settle=True):
        """Runs a command script, expects the exit code (and `err` in stderr), settles. Returns the Result."""
        r = self.foci(script)
        if r.code != code:
            raise Fail("foci %r: exit %d (expected %d): %s" % (script, r.code, code, r.err.strip()))
        if err is not None and err not in r.err:
            raise Fail("foci %r: stderr %r does not contain %r" % (script, r.err.strip(), err))
        if settle:
            self.settle()
        return r

    def run_on(self, window, script, **kw):
        """`foci run --window <id> <script>`; `window` is a fixture name or a window ID."""
        wid = self.wins[window].id if isinstance(window, str) else window
        r = self.foci("run", "--window", wid, script)
        return r

    def status(self):
        r = self.foci("status", "--json", json_out=True)
        if r.code != 0 or r.out is None:
            raise Fail("foci status failed: %s" % r.err.strip())
        r.out.setdefault("project", None)  # nil is omitted from the JSON
        for d in r.out["displays"]:
            d.setdefault("workspace", None)
        return r.out

    def windows(self, *flags):
        """`foci list-windows --json [flags]`, e.g. `windows('--project', 'beta')`."""
        r = self.foci("list-windows", "--json", *flags, json_out=True)
        if r.code != 0 or r.out is None:
            raise Fail("foci list-windows failed: %s" % r.err.strip())
        for w in r.out:
            w.setdefault("project", None)  # nil is omitted from the JSON
            w.setdefault("bundleId", None)
        return r.out

    def workspaces(self):
        r = self.foci("list-workspaces", "--json", json_out=True)
        if r.code != 0 or r.out is None:
            raise Fail("foci list-workspaces failed: %s" % r.err.strip())
        return r.out

    def projects(self):
        r = self.foci("list-projects", "--json", json_out=True)
        if r.code != 0 or r.out is None:
            raise Fail("foci list-projects failed: %s" % r.err.strip())
        return r.out

    def state(self):
        """state.json as Foci saved it ({} if there is none yet). Keys of `windows` are window IDs as strings."""
        try:
            return json.loads((self.home / "state.json").read_text())
        except (OSError, ValueError):
            return {}

    def project(self):
        return self.status()["project"]

    def shown_on(self, display_name):
        for d in self.status()["displays"]:
            if d["name"] == display_name:
                return d["workspace"]
        raise Fail("no display %r in status" % display_name)

    def focused_workspace(self):
        return self.status()["focusedWorkspace"]

    # ------------------------------------------------------------------ waiting

    def wait_until(self, predicate, timeout=5.0, what="condition", interval=0.1, error=None):
        """Polls until `predicate()` is truthy; returns its value. Raises `Fail` (or `error`) on timeout."""
        deadline = time.time() + timeout
        while True:
            value = predicate()
            if value:
                return value
            if time.time() > deadline:
                raise (error or Fail)("timed out after %gs waiting for %s" % (timeout, what))
            time.sleep(interval)

    def snapshot(self):
        r = self.foci("list-windows", "--json")  # also refreshes Foci, which can follow focus
        frames = []
        for p in list(self.probes.values()):
            try:
                frames.append((p.name, json.dumps(p.windows(), sort_keys=True)))
            except (OSError, socket.timeout, ProbeError):
                frames.append((p.name, None))
        return (r.code, r.out, tuple(frames))

    def settle(self, timeout=1.0, interval=0.1):
        """After a command: polls until two reads (list-windows and every probe's window frames) match, max
        `timeout` s. Returns False if the windows were still moving. Accessibility moves are asynchronous."""
        deadline = time.time() + timeout
        prev = None
        while True:
            cur = self.snapshot()
            if cur == prev:
                return True
            prev = cur
            if time.time() > deadline:
                self.unsettled += 1
                return False
            time.sleep(interval)

    def settle_os(self, seconds=3.0):
        """After OS-driven changes (drags, config file saves, display changes, closing windows behind Foci's
        back): Foci refreshes on a 2 s timer, so wait at least 3 s, then settle."""
        time.sleep(seconds)
        return self.settle()

    # ------------------------------------------------------------------ fixture

    def write_config(self, text=None):
        """Writes $FOCI_HOME/config.toml (default: the test config) and returns its text."""
        self.home.mkdir(parents=True, exist_ok=True)
        if text is None:
            text = self.base_config()
        (self.home / "config.toml").write_text(text)
        self.config_text = text
        return text

    def base_config(self):
        """The spec's test config, plus `manage = false` for every other running regular app so that the
        user's windows stay untouched."""
        text = CONFIG_TEMPLATE.replace("@TERMINAL@", self._terminal or terminal_bundle_id())
        skip = {self._terminal, "com.apple.TextEdit"}
        extra = ""
        n = 0
        for b in sorted(set(self._foreign) - skip):
            if b.startswith("dev.foci."):
                continue
            n += 1
            extra += "\n[apps.foreign%d]\nbundle-id = '%s'\nmanage = false\n" % (n, b)
        return text.replace("[[projects]]", extra + "\n[[projects]]", 1)

    def log_lines(self, prefix=None):
        """Lines of $E2E_LOG written by launch commands and probes."""
        try:
            lines = self.log_path.read_text().splitlines()
        except OSError:
            return []
        return [l for l in lines if prefix is None or l.startswith(prefix)]

    def clear_log(self):
        self.log_path.write_text("")

    def fresh(self):
        """Stops Foci, quits the fixture, deletes state and log, writes the test config, starts Foci.
        Fresh state: main shows `c`, the side display `s`, no project."""
        self.stop_foci()
        self.kill_fixture()
        for f in ("state.json", "foci.lock", "foci.sock"):
            try:
                (self.home / f).unlink()
            except OSError:
                pass
        self.write_config()
        self.log_path.write_text("")
        self.start_foci()
        self._displays = None

    def reset_fixture(self, windows="all"):
        """The spec's reset procedure. `windows`: 'all', or the fixture window names to start (no windows: `[]`).
        Ends with alpha active, `w` shown on main, `x` on the side display, `aw` focused."""
        self.fresh()
        self.cmd("workspace x; workspace w; project alpha")
        names = list(FIXTURE_WINDOWS) if windows == "all" else [n for n in FIXTURE_WINDOWS if n in windows]
        self.start_fixture_windows(names)
        self.settle()
        if "aw" in names:
            self.probes["pa"].focus("alpha - web")
            self.wait_until(lambda: self.focused_window() == (self.probes["pa"].pid, "alpha - web"), 5,
                            "aw to be focused", error=SetupError)
        self.settle()
        if "aw" in names and "aw2" in names:
            self.prime_focus()
        self.check_fixture(names)

    def prime_focus(self):
        """After a start the Probe has no key window: `aw` is only the app's default AXFocusedWindow, and a Probe
        `focus` of another window of the same process is ignored until one real focus change happened. Foci's
        `focus next` / `focus prev` (Accessibility raise) is one: it ends with `aw` focused again."""
        pa = self.probes["pa"]
        for _ in range(3):
            if pa.state().get("key") == "alpha - web":
                return
            self.foci("focus next")
            time.sleep(0.4)
            self.foci("focus prev")
            time.sleep(0.4)
        self.settle()

    def start_fixture_windows(self, names):
        """Starts the named fixture windows in the background (`open -g`: a hidden window that becomes focused
        would make Foci switch project to follow it)."""
        procs = []
        for proc, (kind, extra) in FIXTURE_PROCESSES.items():
            mine = [n for n in names if FIXTURE_WINDOWS[n][0] == proc]
            if not mine:
                continue
            self.launch_probe(kind, proc, extra, title=FIXTURE_WINDOWS[mine[0]][1], wait=False)
            procs.append((proc, mine))
        for proc, mine in procs:
            self.wait_probe(proc)
            for n in mine[1:]:
                self.probes[proc].new_window(FIXTURE_WINDOWS[n][1])
        if "te" in names:
            self.start_textedit()
        for n in names:
            proc, title = FIXTURE_WINDOWS[n]
            self.wins[n] = Win(self, n, proc, title)
        self.wait_until(lambda: all(self.wins[n].record for n in names), 20, "Foci to see the fixture windows")

    def check_fixture(self, names):
        for n in names:
            owner, ws = FIXTURE_EXPECT[n]
            r = self.wins[n].record
            if r is None or r["project"] != owner or r["workspace"] != ws:
                raise SetupError("fixture window %s is %s, expected owner %s on %s" % (
                    n, r and (r["project"], r["workspace"]), owner, ws))

    def launch_probe(self, kind, name, args=(), title=None, size=None, wait=True):
        """`open -gna "Probe <KIND>.app" --args [--title T] [--size WxH] <args> --ctl <name>`. Returns the Probe.
        `kind` is a, b or c; `args` are extra process arguments such as ['--group', 'alpha']."""
        app = self.apps / ("Probe %s.app" % kind.upper())
        argv = ["open", "-gna", str(app), "--args"] + list(args)
        if title is not None:
            argv += ["--title", title]
        if size:
            argv += ["--size", size]
        argv += ["--ctl", name]
        try:
            os.unlink(str(self.ctl / (name + ".sock")))
        except OSError:
            pass
        self.ctl.mkdir(parents=True, exist_ok=True)
        p = run(argv)
        if p.returncode != 0:
            raise SetupError("open %s failed: %s" % (app, p.stderr.strip()))
        probe = Probe(name, str(self.ctl / (name + ".sock")), kind)
        self.probes[name] = probe
        if wait:
            self.wait_probe(name)
        return probe

    def register(self, name, proc, title):
        """Names a window a scenario started itself, so `h.wins[name]`, `h.shown(name)` etc. work.
        `proc` is the probe's name (see `launch_probe`). Returns the `Win`."""
        self.wins[name] = Win(self, name, proc, title)
        return self.wins[name]

    def wait_probe(self, name, timeout=15):
        p = self.probes[name]
        self.wait_until(p.alive, timeout, "probe %s to start" % name, error=SetupError)
        p._pid = None

    def wait_window(self, title, probe=None, timeout=10, visible=None):
        """Polls list-windows until a window with this title (of this probe) shows up; returns it."""
        pid = self.probes[probe].pid if probe else None

        def find():
            for w in self.windows():
                if w["title"] == title and (pid is None or w["pid"] == pid):
                    if visible is None or w["visible"] == visible:
                        return w
            return None
        return self.wait_until(find, timeout, "window %r in list-windows" % title)

    def wait_gone(self, title, probe=None, timeout=10):
        pid = self.probes[probe].pid if probe else None
        self.wait_until(
            lambda: not [w for w in self.windows() if w["title"] == title and (pid is None or w["pid"] == pid)],
            timeout, "window %r to disappear from list-windows" % title)

    def start_textedit(self):
        d = self.e2e / "te"
        d.mkdir(parents=True, exist_ok=True)
        f = d / TEXTEDIT_FILE
        f.write_text("e2e\n")
        # -ApplePersistenceIgnoreState: no windows restored from an earlier session.
        p = run(["open", "-g", "-a", "TextEdit", str(f), "--args", "-ApplePersistenceIgnoreState", "YES"])
        if p.returncode != 0:
            raise SetupError("can't start TextEdit: %s" % p.stderr.strip())
        self._textedit_pid = None
        self.wins["te"] = Win(self, "te", "te", TEXTEDIT_FILE)
        self.wait_until(lambda: self.textedit_pid(), 15, "TextEdit to start", error=SetupError)

    def textedit_pid(self):
        p = run(["pgrep", "-x", "TextEdit"])
        pids = p.stdout.split()
        self._textedit_pid = int(pids[0]) if pids else None
        return self._textedit_pid

    def kill_fixture(self):
        """Quits every probe and TextEdit and removes the control sockets."""
        for p in list(self.probes.values()):
            p.quit()
        self.probes = {}
        self.wins = {}
        run(["pkill", "-f", r"Probe [ABC]\.app/Contents/MacOS/Probe"])
        if run(["pgrep", "-x", "TextEdit"]).returncode == 0:
            try:
                osascript('tell application "TextEdit" to quit', timeout=10)
            except Exception:  # noqa: BLE001
                pass
            time.sleep(0.3)
            run(["pkill", "-x", "TextEdit"])
        deadline = time.time() + 5
        while time.time() < deadline and (
                run(["pgrep", "-f", r"Probe [ABC]\.app/Contents/MacOS/Probe"]).returncode == 0
                or run(["pgrep", "-x", "TextEdit"]).returncode == 0):
            time.sleep(0.1)
        if self.ctl.exists():
            for f in self.ctl.glob("*.sock"):
                try:
                    f.unlink()
                except OSError:
                    pass

    # ------------------------------------------------------------------ displays and frames

    def displays(self, refresh=False):
        """`Display`s, main first (system order, so `display-N` is index N+1 here), in Accessibility coordinates."""
        if self._displays is None or refresh:
            self._displays = displays_now()
        return self._displays

    @property
    def main(self):
        return self.displays()[0]

    @property
    def side(self):
        """The display Foci calls `secondary`: the first non-main one from the left."""
        others = sorted(self.displays()[1:], key=lambda d: d.frame.x)
        return others[0] if others else None

    def display_of(self, workspace):
        """The `Display` a workspace lives on, from list-workspaces."""
        for w in self.workspaces():
            if w["name"] == workspace:
                for d in self.displays():
                    if d.name == w["display"]:
                        return d
        raise Fail("no workspace %r" % workspace)

    def probe_of(self, name):
        proc = self.wins[name].proc
        return None if proc == "te" else self.probes[proc]

    def frame(self, name):
        """The frame of a fixture window, as the window server has it (also while parked)."""
        w = self.wins[name]
        if w.proc != "te":
            return self.probes[w.proc].frame(w.title)
        out = osascript('tell application "System Events" to tell process "TextEdit" to get {position, size} of '
                        'window "%s"' % w.title)
        return Rect(*[float(v) for v in out.split(",")])

    def drag(self, name, x, y, w=None, h=None):
        """Moves a Probe window like a user drag. Foci notices at the next refresh (2 s timer)."""
        win = self.wins[name]
        f = self.frame(name)
        self.probes[win.proc].move(win.title, x, y, w or f.w, h or f.h)

    # ------------------------------------------------------------------ focus

    def front_pid(self):
        asn = run(["lsappinfo", "front"]).stdout.strip()
        m = re.search(r"pid\s*=\s*(\d+)", run(["lsappinfo", "info", "-only", "pid", asn]).stdout)
        return int(m.group(1)) if m else None

    def front_bundle(self):
        asn = run(["lsappinfo", "front"]).stdout.strip()
        m = re.search(r'"?bundleID"?\s*=\s*"([^"]+)"', run(["lsappinfo", "info", "-only", "bundleid", asn]).stdout)
        return m.group(1) if m else None

    def focused_window(self):
        """(pid, title) of the system's focused window, as Accessibility has it (the same source as Foci):
        the frontmost app's AXFocusedWindow; title None without one."""
        pid = self.front_pid()
        try:
            out = osascript(
                'tell application "System Events" to tell (first process whose unix id is %d) to get title of '
                '(value of attribute "AXFocusedWindow")' % pid)
            return (pid, out)
        except RuntimeError:
            pass
        for p in self.probes.values():  # no Accessibility permission for the terminal, or no focused window
            try:
                if p.pid == pid:
                    return (pid, p.state()["key"])
            except (OSError, socket.timeout, ProbeError):
                continue
        return (pid, None)

    def wait_focused(self, name, timeout=6):
        """Polls until the fixture window is the system's focused window (focus changes are asynchronous);
        fails with what is focused instead."""
        def ok():
            try:
                self.focused(name)
                return True
            except Fail:
                return False
        try:
            self.wait_until(ok, timeout, "%s to be focused" % name)
        except Fail:
            self.focused(name)  # raises with the details
            raise

    def focus_window(self, name, timeout=6):
        """Makes a shown Probe window the system's focused window like a click, waits for it, settles.
        A freshly started Probe has no key window and ignores `focus` for another window of its own process until
        the window server has focused one of them for real: then Foci's `focus next|prev` (one Accessibility
        raise) is the fallback; it cycles at most through the windows of the workspace."""
        w = self.wins[name]
        pr = self.probe_of(name)
        if pr is not None:
            pr.focus(w.title)
            try:
                self.wait_focused(name, 1.5)
                self.settle()
                return
            except Fail:
                pass
        r = self.rec(name)
        for _ in range(8):
            self.foci("focus next")
            time.sleep(0.4)
            if self.focused_window() == (w.pid, w.title):
                break
        self.wait_focused(name, timeout)
        self.settle()

    def adopt_probe(self, name, kind, timeout=20):
        """Registers a Probe that Foci's launch command started (not the harness) and waits for its socket."""
        p = Probe(name, str(self.ctl / (name + ".sock")), kind)
        self.probes[name] = p
        self.wait_probe(name, timeout=timeout)
        return p

    def terminal_focused(self):
        return self.front_bundle() == self._terminal

    def focus_terminal(self):
        """Brings the runner's own (unmanaged) terminal to the front."""
        run(["open", "-b", self._terminal])
        self.wait_until(self.terminal_focused, 5, "the terminal to be frontmost")
        self.settle()

    # ------------------------------------------------------------------ assertions

    def check(self, condition, message):
        if not condition:
            raise Fail(message)

    def eq(self, actual, expected, what):
        if actual != expected:
            raise Fail("%s: expected %r, got %r" % (what, expected, actual))

    def rec(self, name):
        r = self.wins[name].record
        if r is None:
            raise Fail("window %s is not in list-windows" % name)
        return r

    def shown(self, name):
        """visible: true, and the frame is on its workspace's display."""
        r = self.rec(name)
        self.check(r["visible"], "%s: expected shown, list-windows says hidden" % name)
        d = self.display_of(r["workspace"])
        f = self.frame(name)
        cx, cy = f.center
        self.check(d.frame.contains(cx, cy), "%s: frame %s is not on display %s %s" % (name, f, d.name, d.frame))

    TITLE_BAR = 30  # macOS keeps a window's title bar reachable: a parked window ends up this much above y = maxY - 1

    def parked(self, name):
        """visible: false, and the frame is off-screen in the bottom corner of its workspace's display: x as the
        spec says (`maxX - 1`, or `x - width + 1` with another display to the right), so a 1pt wide strip stays
        on screen. y is `maxY - 1` asked for; the window server pulls it up by at most the title bar height."""
        r = self.rec(name)
        self.check(not r["visible"], "%s: expected parked, list-windows says visible" % name)
        d = self.display_of(r["workspace"])
        f = self.frame(name)
        right = any(o.id != d.id and o.frame.x >= d.frame.maxx - 1 for o in self.displays())
        x = d.frame.x - f.w + 1 if right else d.frame.maxx - 1
        y = d.frame.maxy - 1
        self.check(close(f.x, x) and y - self.TITLE_BAR - 1 <= f.y <= y + 1,
                   "%s: parked at (%g,%g), expected x=%g and y in [%g,%g] (display %s %s)" % (
                       name, f.x, f.y, x, y - self.TITLE_BAR, y, d.name, d.frame))
        for o in self.displays():
            w = min(f.maxx, o.frame.maxx) - max(f.x, o.frame.x)
            h = min(f.maxy, o.frame.maxy) - max(f.y, o.frame.y)
            self.check(w <= 1.01 or h <= 0, "%s: parked window shows %gx%g pt on display %s" % (name, w, h, o.name))

    def maximized(self, name, gap=0):
        """frame = the display's visible frame inset by `gap`."""
        r = self.rec(name)
        d = self.display_of(r["workspace"])
        want = d.visible.inset(gap)
        f = self.frame(name)
        self.check(f.close_to(want), "%s: frame %s, expected maximized %s on %s" % (name, f, want, d.name))

    def focused(self, name):
        """The window is the system's focused window and its app is frontmost."""
        w = self.wins[name]
        pid, title = self.focused_window()
        self.check(pid == w.pid and title == w.title,
                   "focused window is %r of pid %s, expected %s (%r, pid %s)" % (title, pid, name, w.title, w.pid))

    def frame_unchanged(self, name, before, tol=1.0):
        now = self.frame(name)
        self.check(now.close_to(before, tol), "%s moved: %s -> %s" % (name, before, now))

    # ------------------------------------------------------------------ diagnostics

    def diagnostics(self):
        """Text for the report after a failure."""
        out = []
        try:
            out.append("status: " + json.dumps(self.status()))
            for w in self.windows():
                out.append("window %(id)s %(app)s %(title)r project=%(project)s ws=%(workspace)s visible=%(visible)s "
                           "floating=%(floating)s frozen=%(frozen)s" % w)
        except Exception as e:  # noqa: BLE001
            out.append("foci: %s" % e)
        out.append("state.json: " + json.dumps(self.state(), sort_keys=True))
        out.append("e2e.log:\n" + "\n".join(self.log_lines()[-30:]))
        try:
            tail = self.foci_log.read_text().splitlines()[-15:]
            out.append("foci.log:\n" + "\n".join(tail))
        except OSError:
            pass
        return "\n".join(out)


# ---------------------------------------------------------------------- scenario marks


def _mark(fn, **kw):
    meta = getattr(fn, "e2e", None) or {}
    meta.update(kw)
    fn.e2e = meta
    return fn


def needs_displays(n):
    """[2D]: skipped when fewer than `n` displays are connected."""
    return lambda fn: _mark(fn, displays=n)


def one_display(fn):
    """[1D]: skipped unless exactly one display is connected."""
    return _mark(fn, displays=1, exact_displays=True)


def manual(reason="needs a person"):
    """[manual]: always skipped."""
    return lambda fn: _mark(fn, manual=reason)


def questionable(note="questionable behavior"):
    """The expected behavior is flagged as questionable in the spec; shown in the report."""
    return lambda fn: _mark(fn, questionable=note)


def known_issue(note):
    """The spec documents this as a known issue."""
    return lambda fn: _mark(fn, known_issue=note)


def fixture(*names):
    """The standard fixture with only these windows (default: all). `@fixture()` starts none."""
    return lambda fn: _mark(fn, reset="windows", windows=list(names))


def fresh_state(fn):
    """Fresh Foci state only (no project, no windows), see A0."""
    return _mark(fn, reset="fresh")


def keep_state(fn):
    """Depends on the state the previous scenario left. Falls back to `reset_fixture()` if that scenario did not
    pass, or is not the one before in this run."""
    return _mark(fn, reset="keep")

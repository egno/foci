#!/usr/bin/python3
"""End-to-end runner for Foci: python3 Tests/E2E/e2e.py [-k pattern] [--list]

Builds Foci.app, starts it with FOCI_HOME=$E2E_DIR/home (the user's config and state are never touched), runs the
scenarios of Tests/E2E/scenarios/ against real windows (the Probe fixture app and TextEdit), prints a summary and
writes details to $E2E_DIR/report.txt. The user's own Foci is stopped for the run and started again at the end.

Scenarios are functions `def test_B1(h): ...` whose docstring names the spec scenario (Tests/E2E/SCENARIOS.md).
"""
import argparse
import importlib
import os
import pkgutil
import re
import signal
import sys
import time
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import harness  # noqa: E402
from harness import Fail, FatalError, Harness, SetupError  # noqa: E402


class Scenario:
    def __init__(self, module, fn):
        self.module = module
        self.fn = fn
        self.meta = getattr(fn, "e2e", {}) or {}
        m = re.match(r"test_([A-Z]\d+)", fn.__name__)
        self.id = m.group(1) if m else fn.__name__
        self.title = (fn.__doc__ or "").strip().splitlines()[0] if fn.__doc__ else ""

    @property
    def name(self):
        return self.fn.__name__

    def flags(self):
        m = self.meta
        out = []
        if m.get("displays") == 1 and m.get("exact_displays"):
            out.append("1D")
        elif m.get("displays"):
            out.append("%dD" % m["displays"])
        for k in ("manual", "questionable", "known_issue"):
            if m.get(k):
                out.append(k.replace("_", "-"))
        return out


def discover():
    """Every `test_*` function of every module in scenarios/, modules in name order, functions in source order.
    Returns (scenarios, import errors)."""
    import scenarios

    found, errors = [], []
    for info in sorted(pkgutil.iter_modules(scenarios.__path__), key=lambda i: i.name):
        try:
            mod = importlib.import_module("scenarios." + info.name)
        except Exception:  # noqa: BLE001 - one broken module must not hide the others
            errors.append((info.name, traceback.format_exc()))
            continue
        fns = [f for n, f in vars(mod).items() if n.startswith("test_") and callable(f)
               and getattr(f, "__module__", None) == mod.__name__]
        fns.sort(key=lambda f: f.__code__.co_firstlineno)
        found += [Scenario(info.name, f) for f in fns]
    return found, errors


def selected(scenarios, pattern):
    """`-k A` the group, `-k A1` or `A1,B2` exact IDs, anything else a regex over the function name."""
    if not pattern:
        return scenarios
    tokens = [t.strip() for t in pattern.split(",") if t.strip()]

    def match(s):
        for t in tokens:
            if re.fullmatch(r"[A-Z]", t):
                if s.id[:1] == t:
                    return True
            elif re.fullmatch(r"[A-Z]\d+", t):
                if s.id == t:
                    return True
            elif re.search(t, s.name, re.I):
                return True
        return False
    return [s for s in scenarios if match(s)]


class Outcome:
    def __init__(self, scenario, status, seconds=0.0, detail="", notes=()):
        self.scenario, self.status, self.seconds, self.detail, self.notes = scenario, status, seconds, detail, notes


def run_scenario(h, s, previous, n_displays):
    m = s.meta
    if m.get("manual"):
        return Outcome(s, "SKIP", detail="manual: %s" % m["manual"])
    need = m.get("displays")
    if need and (n_displays != need if m.get("exact_displays") else n_displays < need):
        return Outcome(s, "SKIP", detail="needs %s%d display(s), %d connected" % (
            "exactly " if m.get("exact_displays") else "", need, n_displays))
    start = time.time()
    h.unsettled = 0
    try:
        mode = m.get("reset", "windows")
        try:
            if mode == "fresh":
                h.fresh()
            elif mode == "keep" and previous is not None and previous.status == "PASS":
                pass
            elif mode == "windows":
                h.reset_fixture(m["windows"] if "windows" in m else "all")
            else:
                h.reset_fixture()
        except FatalError:
            raise
        except SetupError:
            raise
        except Exception as e:  # noqa: BLE001
            raise SetupError("reset failed: %s: %s" % (type(e).__name__, e))
        s.fn(h)
        notes = ["settle timed out %d time(s)" % h.unsettled] if h.unsettled else []
        return Outcome(s, "PASS", time.time() - start, notes=notes)
    except Fail as e:
        return Outcome(s, "FAIL", time.time() - start, "%s\n%s" % (e, _diag(h)))
    except FatalError:
        raise
    except SetupError as e:
        return Outcome(s, "ERROR", time.time() - start, "setup: %s\n%s" % (e, _diag(h)))
    except Exception:  # noqa: BLE001
        return Outcome(s, "ERROR", time.time() - start, traceback.format_exc() + "\n" + _diag(h))


def _diag(h):
    try:
        return h.diagnostics()
    except Exception as e:  # noqa: BLE001
        return "(no diagnostics: %s)" % e


def write_report(path, outcomes, header, errors):
    lines = header + [""]
    for name, tb in errors:
        lines += ["IMPORT ERROR scenarios.%s" % name, tb, ""]
    for o in outcomes:
        s = o.scenario
        flags = " ".join("[%s]" % f for f in s.flags())
        lines.append("%-5s %-4s %5.1fs  %s %s" % (o.status, s.id, o.seconds, s.title, flags))
        for note in o.notes:
            lines.append("      note: %s" % note)
        for k in ("questionable", "known_issue"):
            if s.meta.get(k) and o.status != "SKIP":
                lines.append("      flagged %s: %s" % (k.replace("_", " "), s.meta[k]))
        if o.detail:
            lines += ["      " + l for l in o.detail.splitlines()]
        lines.append("")
    Path(path).write_text("\n".join(lines) + "\n")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-k", dest="pattern", help="group letter (A), scenario IDs (A1,B2) or a regex over function names")
    ap.add_argument("--list", action="store_true", help="list the scenarios and exit")
    ap.add_argument("--e2e-dir", help="work directory (default: $E2E_DIR or the scratchpad)")
    ap.add_argument("--no-build", action="store_true", help="reuse build/Foci.app and the Probe bundles")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args(argv)

    scenarios, import_errors = discover()
    chosen = selected(scenarios, args.pattern)
    if args.list:
        for s in chosen:
            print("%-4s %-28s %s %s" % (s.id, s.name, s.title, " ".join("[%s]" % f for f in s.flags())))
        for name, _ in import_errors:
            print("import error in scenarios.%s" % name)
        return 0
    if not chosen:
        print("no scenario matches %r" % args.pattern)
        return 2

    h = Harness(args.e2e_dir, build=not args.no_build, verbose=args.verbose)
    signal.signal(signal.SIGINT, signal.default_int_handler)  # also when started in the background
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    signal.signal(signal.SIGHUP, lambda *_: sys.exit(129))
    outcomes = []
    header = ["Foci e2e report, %s" % time.strftime("%Y-%m-%d %H:%M:%S"), "E2E_DIR %s" % h.e2e]
    started = time.time()
    try:
        runnable = [s for s in chosen if not s.meta.get("manual")]
        n_displays = len(harness.displays_now())
        header.append("displays: %s" % ", ".join(d.name for d in harness.displays_now()))
        need_setup = any(
            not (s.meta.get("displays") and (n_displays != s.meta["displays"] if s.meta.get("exact_displays")
                                              else n_displays < s.meta["displays"])) for s in runnable)
        if need_setup:
            h.setup()
        previous = None
        for s in chosen:
            print("%-4s %s ..." % (s.id, s.title), end="", flush=True)
            o = run_scenario(h, s, previous, n_displays)
            previous = o if o.status != "SKIP" else previous
            outcomes.append(o)
            note = (" (%s)" % o.detail.splitlines()[0]) if o.status == "SKIP" else ""
            print("\r%-4s %-5s %5.1fs  %s%s" % (s.id, o.status, o.seconds, s.title, note))
            if o.status in ("FAIL", "ERROR"):
                print("      " + o.detail.splitlines()[0])
    except SetupError as e:
        print("\nsetup failed: %s" % e)
        header.append("SETUP FAILED: %s" % e)
        return_code = 3
    except KeyboardInterrupt:
        print("\ninterrupted")
        header.append("INTERRUPTED")
        return_code = 130
    else:
        return_code = None
    finally:
        h.teardown()

    counts = {k: sum(1 for o in outcomes if o.status == k) for k in ("PASS", "FAIL", "ERROR", "SKIP")}
    summary = "%d passed, %d failed, %d errors, %d skipped in %.0fs" % (
        counts["PASS"], counts["FAIL"], counts["ERROR"], counts["SKIP"], time.time() - started)
    header.append(summary)
    report = h.e2e / "report.txt"
    try:
        h.e2e.mkdir(parents=True, exist_ok=True)
        write_report(report, outcomes, header, import_errors)
    except OSError as e:
        print("can't write report: %s" % e)
    print("\n%s\nreport: %s" % (summary, report))
    if return_code is not None:
        return return_code
    return 1 if counts["FAIL"] or counts["ERROR"] else 0


if __name__ == "__main__":
    sys.exit(main())

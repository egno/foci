# End-to-end scenarios: windows, workspaces, projects

These scenarios run `Foci.app` against real windows and check the outcome through the `foci` CLI and the window
frames. They cover what `Tests/FociCoreTests` checks against fakes, plus what only the real system shows:
Accessibility moves, focus, parking, app restarts, minimize/hide/fullscreen, displays.

Key bindings, key hints and the menu bar are out of scope: keys run the same command scripts as `foci <script>`.

Every expected result below was checked against `Sources/FociCore/Engine.swift`. Behavior the author considers
questionable is flagged **[questionable]**: the scenario pins it down as it is, so a change is noticed on purpose.

## Running

```sh
make e2e                              # all scenarios
python3 Tests/E2E/e2e.py -k A         # a group; -k A1,B2 scenarios; -k regex over the function names
python3 Tests/E2E/e2e.py --list
```

The runner (`Tests/E2E/e2e.py`, scenarios in `Tests/E2E/scenarios/<group>.py`, helpers in `Tests/E2E/harness.py`)
stops your Foci, runs the suite with its own config and state, and starts your Foci again. It prints a
pass/fail/skip summary and writes details to `$E2E_DIR/report.txt`. `$E2E_DIR` defaults to the session scratchpad.
Scenarios marked **[2D]** need two displays and are skipped with fewer, **[1D]** need exactly one, **[manual]**
need a person (cables, sleep) and are always skipped.

## Setup

### Isolation

- The environment variable `FOCI_HOME` is a test-only override: with it set, Foci reads `$FOCI_HOME/config.toml`
  and keeps `state.json`, `foci.sock` and `foci.lock` in `$FOCI_HOME`. It registers no login item and never writes
  the default config over an existing one. The `foci` CLI must run with the same `FOCI_HOME` to find the socket.
  `~/.config/foci` and `~/Library/Application Support/Foci` are never touched.
- The runner stops the user's Foci with `pkill -TERM -x foci` (it restores the parked windows), builds with
  `make app`, writes the [test config](#test-config) to `$E2E_DIR/home/config.toml`, and starts
  `build/Foci.app/Contents/MacOS/foci` with `FOCI_HOME=$E2E_DIR/home`, `E2E_DIR` and `E2E_LOG` in its environment
  (the launch commands use them). At the end, also after a failure or Ctrl-C, it stops that Foci and starts the
  user's again with `open ~/Applications/Foci.app`.
- The runner's own terminal must not be managed: `[apps.runner]` with the terminal's bundle ID and
  `manage = false`. The runner does the same for every other regular app that is running, so the suite never moves
  the user's windows. TextEdit must not be running at the start (the suite closes its windows).
- Stay on one Space and turn off Stage Manager.
- Keep `$E2E_DIR` short: Foci's socket path must be below 104 bytes (`/private/tmp` is spelled `/tmp`).

### Fixture app

A tiny AppKit app, `Tests/E2E/Probe` (its own SwiftPM package, bundled by `Tests/E2E/Probe/build.sh`), with
standard titled, resizable windows. It is bundled three times into `$E2E_DIR/apps/` with different bundle IDs, so
one process can hold windows of several projects (like Chrome) and apps can be told apart: `Probe A`
(`dev.foci.probe.a`), `Probe B` (`dev.foci.probe.b`), `Probe C` (`dev.foci.probe.c`). Ad hoc signed; Probe needs no
Accessibility permission.

```
open -gna "$E2E_DIR/apps/Probe B.app" --args --group alpha --title 'alpha term' --ctl <name> [--size WxH]
```

- `--group` only stays in the process arguments (for `args` rules), `--title` is the first window's title (for
  `title` rules), `--ctl` names the control socket. On start Probe logs `probe-start <name> <argv>` to `$E2E_LOG`.
- Always start with `open -g`: a hidden window that becomes focused makes Foci switch project to follow it.
- The control socket `$E2E_DIR/ctl/<name>.sock` takes one command per line and answers one line, `ok …` or
  `err …`. Titles with blanks are quoted like in a shell.

| Command | Does |
|---|---|
| `new-window <title>`, `close <title>`, `rename <old> <new>` | |
| `focus <title>` | activates the app and makes that window key (Cmd-Tab, the Dock and `open -a` can't target one window) |
| `frame <title>` | prints `x y w h`, top-left origin, global coordinates: the same as Accessibility |
| `move <title> x y w h` | simulates a user drag (Foci doesn't observe moves; it notices at the next refresh) |
| `minimize <title>`, `unminimize <title>`, `fullscreen <title>` | |
| `hide`, `unhide` | the app, like Cmd-H |
| `spawn <shell cmd>` | runs a child process of the Probe process, waits, prints its exit code |
| `pid`, `quit` | |
| `id <title>`, `list`, `state` | extras: window ID; windows with frames as JSON; frontmost and key window |

Native fullscreen moves the window to a Space of its own, and the windows of the other Space disappear from
Accessibility while it lasts: `list-windows` is short during I3.

### Observables

| What | How |
|---|---|
| Owner, workspace, visible, floating, frozen | `foci list-windows --json` (`project` is absent for unlinked windows) |
| `manual`, `app`, `seq`, `floatingFrame`, `lastFocused`, `previousProject` | `state.json` (`list-windows` doesn't show them) |
| Active project, focused workspace, workspace per display | `foci status --json` |
| Layout and window count per workspace | `foci list-workspaces --json` |
| Focused window | Accessibility `AXFocusedWindow` of the frontmost app (System Events), or the Probe's `state` |
| Frames | Probe `frame <title>`; System Events for TextEdit (the CLI shows no frames) |
| Display frames | `NSScreen`, converted to Accessibility coordinates (`y = mainHeight - maxY`) |
| Launches | the launch templates write marker lines with `printf` to `$E2E_LOG`, see [Test config](#test-config) |
| Events | `foci subscribe` running in the background, one JSON line per change |
| Persistence | `state.json` after the step |

`{url}` and `{open}` are shell-quoted by Foci, so the printf lines show the unquoted values, one line per
argument (`printf 'arg %s\n' {open}`). Don't use `echo "…{open}"`: the quotes break.

Shared assertions, used below by name (tolerance ±1 pt):

- **shown(W)**: `visible: true` and W's frame is on its workspace's display, per the layout.
- **parked(W)**: `visible: false` and W's frame is off-screen in a bottom corner of its workspace's display:
  `x = display.maxX - 1`, or `x = display.x - width + 1` when another display is to the right, `y = display.maxY - 1`.
  No visible part of W on any display except a 1pt wide strip. macOS pulls a parked window up by its title bar
  (measured: `y = maxY - 28`), so the runner accepts `y` between `maxY - 31` and `maxY`.
- **maximized(W)**: frame = the display's visible frame inset by `gap`.
- **focused(W)**: W is the system's focused window and its app is frontmost.

### Timing

- After a command: poll until two reads match (`list-windows` and the probes' frames), max 1 s. Accessibility moves
  are asynchronous. `status` and `list-*` refresh Foci themselves, which can follow focus; read them after the
  window has settled, not while a focus change is in flight.
- After OS-driven changes (drags, config file saves, display changes, windows closed behind Foci's back) wait at
  least 3 s, then settle: Foci refreshes on a 2 s timer.

### Test config

The runner adds `manage = false` apps for the user's other running apps after `[apps.runner]`.
`<terminal>` is the runner's terminal bundle ID.

```toml
gap = 0
accordion-padding = 0

[workspaces]
w = 'main'
c = 'main'
x = 'secondary'
s = 'secondary'

[apps.runner]                   # the terminal running the suite: never managed
bundle-id = '<terminal>'
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

[apps.notes]                    # its own bundle: new windows join the active project if it uses notes
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
```

Notes on the rules:

- Linking walks the apps of the window's bundle by id. Any Probe A window that matches no title rule is an unlinked
  `web` window on `w`.
- A window that matches no rule of a bundle falls back to the first per-project app of that bundle by id. Keep each
  Probe bundle to one per-project def where possible: Probe A has `web`, Probe C has `notes`; Probe B has `editor`
  and `term`, so its fallback is `editor` (see A10).
- `notes` has its own bundle and a title rule. Without `{project}` in a rule it would be linked to alpha by the rules
  and `new-windows` would never apply (see A5).

### Standard fixture

Unless a scenario says otherwise: two displays, `main` and `side` (the first display that isn't main from the left),
active project `alpha`, `w` shown on `main` (focused), `x` shown on `side`, and these windows:

| Name | Started as | Owner | Workspace |
|---|---|---|---|
| `aw` | Probe A `--title 'alpha - web'` | alpha | w |
| `bw` | same Probe A process, window `beta - web` | beta | w |
| `aw2` | same Probe A process, window `alpha - web 2` | alpha | w |
| `at` | Probe B `--group alpha --title 'alpha term'` | alpha | x |
| `bt` | Probe B `--group beta --title 'beta term'` | beta | x |
| `ae` | Probe B `--group alpha-edit --title 'alpha editor'` | alpha | c |
| `ch` | Probe B `--group chat --title chat` | – | s |
| `te` | a TextEdit document window (`te.txt`) | – | w |

Seq order on `w` is creation order: `aw`, `bw`, `aw2`, `te`.

**Reset procedure.** On a fresh state main shows `c`, the side display shows `s`, and no project is active, so
windows that the table puts on `w` and `x` don't land there by themselves. Every scenario starts with:

1. Stop Foci and delete the test state (`$FOCI_HOME/state.json`); quit the fixture windows.
2. Start Foci.
3. `foci 'workspace x; workspace w; project alpha'`: main shows `w`, side `x`, alpha is active, and the previous
   project is none.
4. Start the fixture windows in the background with `open -g`, so a hidden window never becomes focused (a focused
   hidden window makes Foci switch project to follow it). `te` last.
5. `focus aw` (Probe `focus`).

---

## A. Discovery and linking by rules

**A0 Fresh state.** [2D] Fresh state, before the reset. Expect: main shows `c`, `side` shows `s`, `status.project`
null, focused workspace `c`. `foci project-back-and-forth` exits 0 and changes nothing (status and `state.json`).

**A1 Rules link new windows and place them on the app's workspace.** [2D] Reset without windows, `alpha` active.
Start `aw`, `bw`, `at`, `bt`, `ch`.
Expect: owners and workspaces as in the fixture table; `bw`, `bt` parked; `aw`, `at` shown (maximized); `ch` parked
(`s` not shown).

**A2 Unmatched window is unlinked on the focused workspace.** Focus `w`, open TextEdit (`te`).
Expect: `te` `project: null`, `workspace: w`, shown. After `foci project beta` and `foci project --none` it is still shown.

**A3 `manage = false` windows are ignored.** Start Probe B `--group ignored`.
Expect: not in `list-windows`; drag it anywhere and switch projects/workspaces: its frame never changes.

**A4 `floating = true` app.** Start Probe B `--group dialog` at 400x300 in the middle of `main`.
Expect: `floating: true`, frame unchanged (not maximized), not counted as a tile when `w` is in tiles.

**A5 `new-windows = 'active-project'`.** `notes` has its own bundle (Probe C) and a title rule `^{project} notes$`.
`alpha` active: start a Probe C window `untitled`. Expect owner `alpha` (alpha uses `notes`).
`foci project --none`, a second window `second`. Expect it unlinked.
`foci project beta` (beta doesn't use `notes`), a third window `third`. Expect unlinked.
A window titled `alpha notes` goes to alpha by the title rule, whichever project is active (parked while beta is).

**A6 Renamed window gets linked by a title rule.** In Probe A open `scratch` (unlinked, on `w`). Rename to `beta - web`.
Expect owner `beta`, parked (alpha active).

**A7 Manual unlink beats title rules.** `foci run --window <aw> unlink`, then rename `aw` (any title change that
still matches, e.g. `alpha - web 3`). Expect still unlinked; `manual: true` in `state.json`.

**A8 Closed windows disappear.** Close `bw`. Expect it gone from `list-windows`, `list-projects` beta count −1,
and its ID absent from `windows` in `state.json`. `lastFocused` keeps the ID (known; harmless).
Closing the focused window of a tiled workspace re-tiles the rest (see F11).

**A9 App restart re-links by rules.** [2D] `alpha` active, `w` in tiles. Quit Probe B (`at`, `bt`, `ae`, `ch` vanish),
relaunch the same commands. Expect new window IDs with the same owners and workspaces; the old IDs dropped from
`state.json`; `aw`, `aw2` untouched.

**A10 Fallback def.** **[questionable]** Start Probe B `--group other`: it matches no rule. A window that matches
no rule falls back to the first per-project app of its bundle by id, here `editor`. Expect: unlinked (`project:
null`), `state.json` app `editor`, on workspace `c` from that def (parked while `c` isn't shown). Switching to `c`
would also autostart alpha's editor. B11 relies on this fallback.

---

## B. Projects

**B1 Switch hides other projects on every display; unlinked windows stay.** [2D] `foci project beta`.
Expect `bw`, `bt` shown; `aw`, `at` parked; `te` shown; focused workspace still `w`; `status.project = beta`.

**B2 No project.** `foci project --none`. Expect every linked window parked, `te` and unlinked windows on shown
workspaces shown; `status.project = null`.

**B3 Cycle.** From `alpha`: `foci project next` → beta, `next` → alpha (wraps), `prev` → beta.
From none: `next` → alpha (first), `prev` → beta (last).

**B4 Back and forth.** After the reset the previous project is none. From alpha: `project-back-and-forth` → none
(`project: null`), again → alpha. Then `project beta`, `project-back-and-forth` → alpha, again → beta.
After `project --none`, back-and-forth returns to the project before it. The "no previous project" case only exists
in A0.

**B5 Unknown project.** `foci project nope`: exit 1, stderr `unknown project 'nope'`, nothing moves, state unchanged.

**B6 Same project is a no-op for windows.** `foci project alpha` while alpha active: no window moves,
`previousProject` unchanged, but focusBest and autostart still run: focus goes to the best window of the focused
workspace, and a missing window of an app on a shown workspace is launched.

**B7 Focus is restored per project and workspace.** alpha: two windows on `w` (`aw`, `aw2`), focus `aw2`.
`project beta`, focus `bw`. `project alpha` → focused(`aw2`). `project beta` → focused(`bw`).

**B8 Focusing a hidden window follows it.** alpha active on `w`. Focus `bw` from outside Foci with the Probe's
`focus` command (it activates the app and makes that window key; Cmd-Tab, the Dock and `open -a` can't target one
window of an app, they remain for manual checks). Expect project → beta, `w` shown, focused(`bw`).
Same for `bt` on `x` (other display): project beta, `x` shown on `side`, focused workspace `x`.

**B9 Stale focus at startup doesn't switch.** beta active, focus `bw`. Run `foci workspace q`: `bw` is parked but
still focused. `pkill -TERM foci` and start Foci again. Expect the project and the focused workspace unchanged;
`bw` is parked again.

**B10 Autostart on switch, shown workspaces only.** Close `ae`. `foci 'project beta; workspace c'` (no launch: beta
has no editor), then `foci project alpha`: exactly one editor launch in `$E2E_LOG`: `launch editor alpha`
followed by exactly one `arg …/src/alpha api` line (the path is one argument, `$HOME` expanded). Repeating the
switch within 30 s doesn't launch again. Switching projects while only `w` and `x` are shown launches nothing
(`editor` lives on `c`). The new window is linked to alpha on `c`.

**B11 Window from a launch is linked by the pending launch.** Relies on the fallback of A10: a Probe B window
without a matching `args` rule is an `editor` window (unlinked, on `c`), so the pending launch decides. Start a
`--group other` window ≤30 s after an alpha launch of `editor`: it is linked to alpha; after 30 s it is not.

**B12 Project removed from config.** Delete `beta` from the config and save (the config reloads on save, ≥3 s).
Expect `bw`, `bt` unlinked and shown on their workspaces; if beta was active, `status.project = null`.
Add it back: windows are re-linked by rules (`bw` title, `bt` args).

**B13 Layout per project.** alpha: `foci 'workspace w; layout tiles'`. `project beta`: `w` maximized.
`project alpha`: `w` tiles again. `list-workspaces` reports the active project's layout.

**B14 Back and forth to a removed project.** `project beta`, `project alpha`, then delete `beta` from the config and
save (≥3 s). `foci project-back-and-forth`: exit 1, stderr `unknown project 'beta'`, alpha stays active. A window
manually linked to beta (`link beta`) is unlinked when beta goes, and stays unlinked after beta is added again:
`manual` stays true, while rule-linked windows are re-linked.

**B15 Reload errors.** `foci reload-config` with a TOML syntax error in the file: exit 1, stderr starts with
`config: `, and the old config stays in effect (projects, apps). With a validation problem (a project that
references an unknown app): exit 1, stderr lists the problems, and the new config is in effect.

---

## C. Workspaces

**C1 Switch changes only its display.** [2D] `foci workspace c`. Expect `ae` shown, `aw`, `te` parked, `side`
still shows `x` with `at` shown, focused(`ae`), `previousWorkspace = w`.

**C2 Switch to a workspace on the other display moves focus there.** [2D] `foci workspace s`.
Expect `side` shows `s` (`ch` shown, `at` parked), `main` still shows `w`, focused(`ch`), `status.focusedWorkspace = s`.

**C3 Ad hoc workspace.** Focus on `side`, `foci workspace q` (not in config). Expect `q` on `side`, empty,
`at` parked. `foci workspace w`, `foci workspace q`: still on `side`. Persisted in `state.json` `workspaceDisplay`.

**C4 Cycle stays on the display.** [2D] On `main` (`w`, `c`, plus ad hoc ones there, sorted by name):
`workspace next` from `w` wraps to `c`; workspaces of `side` are never picked.

**C5 Back and forth.** `w` → `workspace c` → `workspace-back-and-forth` → `w` → again → `c`. Across displays
(`w` → `s` → back) the focus returns to `main`.

**C6 Empty workspace.** Use an empty ad hoc workspace `q` (an empty `c` triggers the editor autostart):
`foci workspace q`: exit 0, every window of `w` parked, nothing focused by Foci (the frontmost app keeps focus).

**C7 Autostart on workspace switch.** Close `ae`, `foci workspace c`: one editor launch for alpha. No launch for
`autostart = false` apps (`web`, `term`) when their workspace is empty.

**C8 Parking geometry.** [2D] After C1: `aw` and `te` parked on `main` (on a layout where `side` is to the right,
`x = main.x - width + 1`; otherwise `x = main.maxX - 1`); `bt` parked on `side`. Moving a mouse along the bottom
edge never reveals more than 1pt of width.

**C9 Workspace counts.** `foci list-workspaces --json` lists `w`, `c` on `main` and `x`, `s` on `side`
(plus ad hoc ones), `shown`/`focused` per `status`, `windows` = windows of the active project + unlinked, minus frozen.

**C10 `previousWorkspace` comes from workspace switches only.** **[questionable]** `focus-display` and
`move-to-display --follow` change the focused workspace without setting `previousWorkspace`. `foci 'focus-display
next; workspace-back-and-forth'` from `w` (previous is `x` after the reset): the focus is on `x` already, so
back-and-forth stays on `x` instead of returning to `w`.

---

## D. Moving windows

**D1 Move to a workspace without following.** Focus `aw`, `foci move-to-workspace c`.
Expect `aw` workspace `c`, parked; focused workspace still `w`; focused(`aw2`) (the first remaining window in `w`).

**D2 Move and follow.** `foci move-to-workspace --follow c`. Expect `c` shown, `aw` shown with `ae`, focused(`aw`).

**D3 Move to an ad hoc workspace.** `foci move-to-workspace --follow z`. `z` is created on the display of the
focused *workspace* (not of the moved window) and shown there. With `foci run --window <at> 'move-to-workspace z2'`
while `w` is focused: `z2` ends up on `main`, although `at` lives on `side`.

**D4 Move to the other display.** [2D] Focus `aw`, `foci move-to-display next`.
Expect `aw` on `x` (the workspace shown on `side`), shown on `side`, focus goes to `aw2` on `main`.
With `--follow`: focused workspace `x`, focused(`aw`). `prev` from `main` wraps to `side` too (two displays).

**D5 Move to display with one display.** [1D] `move-to-display next`: exit 0, nothing changes.

**D6 Move a workspace to the other display.** [2D] Focus `w`, `foci move-workspace-to-display next`.
Expect `w` on `side` with `aw`, `te` maximized there; `x` no longer shown; `main` shows another of its
workspaces (`c`, or the last it showed); persisted. `move-workspace-to-display prev` moves it back; `x` reappears
on `side` (display history). After a move, editing `w`'s display in the config (and reloading) has no effect: the
`state.json` override wins.

**D7 Move a workspace off the only workspace of a display.** [2D] `side` shows `x` and also owns `s`. Move both off:
`x` to `main`, then show `s` on `side` and move it to `main` too. Only then does `side` show a new `display-N`
workspace, where N is the display's index in the system display order (`NSScreen.screens`, not left to right).

**D8 Moving a floating window to another display centers it.** [2D] Float `aw` (F8), `move-to-display next`.
Expect `aw` centered on `side`'s visible frame, size clamped to it.

**D9 No focused window.** Focus the desktop (Finder with no windows): `foci move-to-workspace c` → exit 1
`no focused window`. Same for `move-to-display`, `link`, `unlink`, `float`, `resize`.

**D10 Explicit window, even hidden.** `foci run --window <bw> 'move-to-workspace c'` while alpha active:
`bw` moves to `c`, stays parked, alpha's windows untouched. `foci run --window <bw> reveal`: beta active, `c` shown,
focused(`bw`).

**D11 Unknown explicit window.** `foci run --window 999999 reveal` → exit 1 `no window`. Other window commands
(`move-to-workspace c`, `move-to-display next`, `link beta`, `unlink`, `float`, `resize +10`) → exit 1
`no focused window`, and `move next` → `no focused tiled window`.

**D12 Focused window that is parked.** beta active, focus `bw`, `foci workspace q`: `bw` is parked and still the
focused window. Window commands (`move-to-workspace c`, `link`, `unlink`, `float`, `resize +10`) → exit 1
`no focused window`. **[questionable]** Focusing the same window again doesn't follow it (only a change of the
focused window does): `w` stays hidden and `bw` parked. Focusing another hidden window does follow.

---

## E. Focus

**E1 Cycle within the workspace.** `w` has `aw`, `aw2`, `te` (seq order = creation order). `foci focus next`
three times: each in order, wrapping. `prev` goes back. Windows of beta and parked workspaces are skipped.

**E2 Frozen windows are skipped.** Minimize `aw2`: `focus next` cycles `aw` ↔ `te`.

**E3 Nothing focused yet.** Focus the unmanaged runner terminal (nothing in the list is focused), then `foci focus
next`: the first window gets focus. (A window of another display's workspace focused instead: `focus next` goes to
the first, too.)

**E4 Focus the other display.** [2D] `foci focus-display next`: focused workspace `x`, focused(last focused alpha
window on `x`, else the first). `prev` back to `w` with its last focused window.

---

## F. Layout

**F1 Maximized by default.** Every non-floating shown window = maximized; with `gap = 10`, inset by 10 on all sides.

**F2 Tiles side by side on landscape.** `w` with `aw`, `aw2`, `te`: `foci layout tiles`.
Expect three equal columns in seq order, gap between and around them, full height of the visible frame.

**F3 Tiles stacked on portrait.** [2D, `side` portrait] `foci 'workspace x; layout tiles'` with two windows: rows.

**F4 Toggle and orientation.** `layout toggle` flips tiles ↔ maximized. `layout toggle-orientation` on
maximized landscape → tiles stacked; again → side by side.

**F5 Move swaps with its neighbour.** Tiles `[aw, aw2, te]`, focus `aw`: `move next` → `[aw2, aw, te]`,
focused(`aw`); `move prev` → `[aw, aw2, te]`; `move prev` again wraps → `[te, aw2, aw]` (`aw` swaps with the last).
Order persists across project switches and restarts. Floating focused window: exit 1 `no focused tiled window`.

**F6 Resize by points.** Two tiles on a 2560pt-wide display, gap 0: `resize +200` → focused tile 1480, other 1080.
`resize -200` → back to 1280/1280. Repeated `+1000` stops at 95 %; repeated `-1000` at 5 %.
In maximized or with one tile: exit 0, no change.

**F7 Balance.** After F6, `balance` → equal tiles. Weights of other workspaces are untouched.

**F8 Float.** Focus `aw2` in tiles, `foci float`. Expect `aw2` at 70 % of the visible frame, centered (15 % margins),
focused, other tiles re-split. `float` again → back into the tiles at its old position.

**F9 Floating frame is remembered.** Drag the floating `aw2` to a corner, `project beta`, `project alpha`:
`aw2` returns to the dragged frame. Same after `workspace c; workspace w` and a Foci restart. The frame is captured
only while the window is shown and on screen, not while it is parked. A floating window dragged onto the other
display (still on screen) is re-centered on its own workspace's display at the next refresh.

**F10 User drags of managed windows snap back.** Drag or resize a tiled/maximized window with the mouse,
then any refresh (focus change): it returns to its planned frame.

**F11 Windows coming and going re-tile.** In tiles, open a new alpha `web` window → it joins at the end, tiles
re-split. Close the middle one → the rest fill the space.

**F12 Initial layout from config.** Change `c = 'main'` to `[workspaces.c] display = 'main'` + `layout = 'tiles'`, save:
a project that never set `c` gets tiles; one that did keeps its runtime choice.

**F13 Accordion.** With `accordion-padding = 30` and three windows on a maximized `w`, the focused one is
inset 30 pt from each side that has windows before or after it, and the others fill the rest of the area, so
their edges show. `focus next` slides the accordion; the first and last windows have no strip on their open side.

---

## G. Manual linking

**G1 Link to another project.** Focus `te`, `foci link beta`. Expect `te` owner beta, parked (alpha active), focus
moves to the best remaining window of `w`. `manual: true` is not in `list-windows`: read it from `state.json`.

**G2 Link to the active project.** Focus `te` (unlinked), `foci link --active` → owner alpha, still shown;
`project beta` parks it. With no active project: exit 1 `no active project`.

**G3 Unknown project.** `foci link nope`: exit 1 `unknown project 'nope'`.

**G4 Unlink.** Focus `aw`, `foci unlink`. `aw` stays shown after `project beta` and `project --none`;
renaming it does not re-link it (manual).

**G5 One process, several projects.** `aw` and `bw` belong to the same Probe A process: switching projects parks
one and shows the other, on the same workspace, without hiding the app (no Cmd-H effect, Dock shows it running).

**G6 Manual links don't survive the app's restart.** Link TextEdit (`te`) to beta, quit and reopen TextEdit
(new window ID): it comes back unlinked (no rule). Document: rules are the durable way to link.

---

## H. Launch

**H1 Focus an existing window.** alpha active on `c`: `foci launch web` → `w` shown, focused(`aw`), no launch logged.

**H2 Launch for the project.** Close every alpha `web` window: `foci launch web` →
`launch web alpha` logged (`FOCI_PROJECT=alpha`); the new window linked to alpha on `w`. A second
`launch web` within 30 s before the window appears does not launch again.

**H3 Outside the project.** `project --none`: `foci launch web` → focuses the newest unlinked `web` window if any,
else `global web` logged. `launch term` (no global-launch): exit 1 `app 'term' has no global-launch command`.

**H4 Unknown app.** `foci launch nope`: exit 1 `unknown app 'nope'`.

**H5 `{open}` is quoted.** H2 for `editor`: the logged line is `arg <HOME>/src/alpha api`, one argument.

**H6 A launch links the next unmatched window.** **[questionable]** Within 30 s of an alpha `launch web`, any
unmatched `web` window (e.g. `personal - web`, from global-launch or another Probe A process) is linked to alpha
too, not only the launched one. After 30 s it stays unlinked.

**H7 Minimized windows and autostart.** With only a minimized alpha editor window: `workspace c` → no autostart
(the window still counts); `launch editor` → a new launch (a frozen window isn't focused).

**H8 No global launch.** `launch editor` while beta is active → exit 1 `app 'editor' has no global-launch command`.

---

## I. Minimized, hidden, fullscreen

**I1 Minimized windows keep their record and are not moved.** Minimize `aw`: `frozen: true`, owner and workspace
kept. `project beta`, `project alpha`: no frame call on it. Unminimize while beta is active: `aw` is parked on the
next refresh; unminimize while alpha on `w`: shown and laid out.

**I2 App hidden (Cmd-H).** Hide Probe A: `aw`, `bw` frozen. Unhide: each goes back to shown or parked per the rules.

**I3 Native fullscreen.** Fullscreen `aw`: frozen, Foci doesn't touch it, it isn't a tile. Leave fullscreen: laid out
again. (The window gets a Space of its own; the other windows vanish from Accessibility meanwhile.)

**I4 Frozen windows don't count.** `list-workspaces` windows count and `focus next` exclude them; `launch web`
starts a new window when the only alpha `web` window is minimized.

---

## J. Displays

**J1 Disconnect a display.** [2D, manual or virtual] Focus `x` on `side`, disconnect `side`.
Expect `x` and `s` now on `main`, `x` shown and focused with `at`; `w` parked. Nothing remains off-screen at the
old `side` coordinates.

**J2 Reconnect.** Reconnect `side`: it shows `x` again (display history), `main` shows `w` again with its windows.

**J3 Sleep / no displays.** Close the lid with no external display, wake: no frames changed while asleep, state
unchanged, commands during the gap return `no displays` (exit 1).

**J4 New display with nothing to show.** Connect a third display: it shows `display-3`; `foci workspace display-3`
works; ad hoc workspaces created while focused there live on it.

**J5 Arrangement change.** Move `side` to the left of `main` in System Settings: parking corners flip (C8),
`focus-display next/prev` follows the new left-to-right order.

**J6 A `display-N` name can be reused by a new display.** [2D, manual or virtual] **Known issue.** The placeholder
workspace of a display with nothing to show is named `display-N` after the display's index and is stored in
`workspaceDisplay`. When a different display later needs a placeholder at the same index, the same name is
pointed at the new display, and windows on it move there.

---

## K. State, quit, CLI

**K1 Persistence across restarts.** After a mix of B–G, `pkill -TERM -x foci`, start again.
Before the restart every window is on screen (restoreAll), maximized/tiled per its workspace's display.
After: same active project, workspaces per display, owners, manual flags, layouts, weights, order, floating
frames; parked windows parked again.

**K2 Quit restores windows.** `pkill -TERM -x foci`: no window remains parked; floating windows at their frames.

**K3 Old state files.** Start with a `state.json` missing newer keys (`layouts`, `seq`, `weight`, `displayHistory`):
loads, defaults applied. **[questionable]** A file without `nextSeq` gives new windows `seq` values that collide
with the old windows' (the counter restarts at 0): order between them falls back to window ID.

**K4 Scripts and exit codes.** `foci 'workspace c; layout tiles; workspace w'` runs in order. `foci 'project nope;
workspace c'`: exit 1 with the error, `c` still shown. `foci bogus` → exit 2 before reaching the app. App not
running → exit 3 (`FOCI_HOME` pointing at an empty directory).

**K5 Subscribe.** `foci subscribe` emits one status line per project/workspace/display change, none for no-ops
(B6, D5).

**K6 URL router switches projects.** With `bt` focused, run `foci open https://x` as a child process of its Probe
process (`spawn`, so that the opener's ancestry is a Probe window's process): project beta, `w` shown, `bw`
focused, `open-url https://x beta` logged (unquoted). From `ch` (unlinked) the same goes to the active project's
web window.

**K7 `exec`.** `foci exec printf 'exec %s\n' "$FOCI_PROJECT" >> "$E2E_LOG"` runs the command with `FOCI_PROJECT` set
to the active project (empty without one); the rest of the script is the command, `;` included.

**K8 Modes.** `foci mode main` exits 0; `foci mode nope` exits 1 `unknown mode 'nope'`; `status.mode` stays `main`.

---

## Coverage map

| Command | Scenarios |
|---|---|
| `project <name>/--none/next/prev`, `project-back-and-forth` | B1–B7, B13, B14, A0 |
| `workspace <name>/next/prev`, `workspace-back-and-forth` | C1–C7, C10 |
| `move-to-workspace [--follow]` | D1–D3, D9–D12 |
| `move-to-display [--follow]` | D4, D5, D8 |
| `move-workspace-to-display` | D6, D7 |
| `focus-display`, `focus` | E1–E4, C10 |
| `move`, `layout`, `resize`, `balance`, `float` | F2–F9, D11, D12 |
| `link`, `unlink` | G1–G6, A7, B14 |
| `reveal`, `run --window` | D10, D11, A7 |
| `launch`, autostart | H1–H8, B10, B11, C7 |
| `exec` | K7 (the launch templates run through the same shell launcher: B10, H2) |
| `mode` | K8 |
| `reload-config` | B12, B14, B15, F12 |
| `foci open` | K6 |
| `foci subscribe` | K5 |
| `foci status`, `list-windows`, `list-workspaces`, `list-projects` | used by every scenario; C9 |
| exit codes: 0 ok, 1 command failed, 2 usage error, 3 app not running | B5 and D9/D11 (1), K4 (1, 2, 3) |
| OS events (focus, rename, close, minimize, hide, fullscreen, displays, app restart) | A6–A9, B8, B9, I1–I4, J1–J6 |
| State file (`state.json`, `FOCI_HOME`) | A0, A8, A9, C3, D6, K1–K3 |

# End-to-end scenarios: windows, workspaces, projects

These scenarios run the installed `Foci.app` against real windows and check the outcome through the `foci` CLI
and the window frames. They cover what `Tests/FociCoreTests` checks against fakes, plus what only the real
system shows: Accessibility moves, focus, parking, app restarts, minimize/hide/fullscreen, displays.

Key bindings, key hints and the menu bar are out of scope: keys run the same command scripts as `foci <script>`.

## Setup

### Isolation

- Back up `~/.config/foci/config.toml` and `~/Library/Application Support/Foci/state.json`, install the
  [test config](#test-config), delete `state.json`, then `make install`. Restore both afterwards.
  (Both paths are hard-coded; an env override such as `FOCI_HOME` would let the suite run without touching them.)
- Quit every app with standard windows except the terminal running the suite. The terminal is unlinked; its
  window is `term0` below.
- Turn off "Displays have separate Spaces" side effects by staying on one Space; turn off Stage Manager.

### Fixture app

A tiny AppKit app, `Probe.app`, bundled twice with different bundle IDs (`dev.foci.probe.a`, `dev.foci.probe.b`),
so one process can hold windows of several projects (like Chrome) and two apps can be told apart:

```
open -na Probe --args --group <g> --title '<t>' [--windows N] [--size 800x600]
```

- `--group` lands in the process arguments (for `args` rules), `--title` is the window title (for `title` rules).
- A control socket or stdin accepts `new-window <title>`, `close <title>`, `rename <old> <new>`, `minimize`,
  `fullscreen`, `hide`, `frame <title>` (prints `x y w h` in Accessibility coordinates), `quit`.

Without the fixture, TextEdit (titles) and `kitty --instance-group` (args) cover most scenarios, and
`osascript -e 'tell application "System Events" to get {position, size} of window 1 of process "kitty"'` reads frames.

### Observables

| What | How |
|---|---|
| Owner, workspace, visible, floating, frozen | `foci list-windows --json` |
| Active project, focused workspace, workspace per display | `foci status --json` |
| Layout and window count per workspace | `foci list-workspaces --json` |
| Focused window | fixture `frame`/AX `focused window`, or `foci list-windows` + `osascript` frontmost |
| Frames | fixture `frame <title>` / System Events (the CLI shows no frames; adding `frame` to `WindowDTO` and display frames to `StatusDTO` would make the suite self-contained) |
| Launches | `launch` commands write a marker: `exec`-style `echo "$FOCI_PROJECT {project}" >> $E2E_LOG` before `open` |
| Events | `foci subscribe` running in the background, one JSON line per change |
| Persistence | `state.json` after the step |

Shared assertions, used below by name:

- **shown(W)**: `visible: true` and W's frame is on its workspace's display, per the layout.
- **parked(W)**: `visible: false` and W's frame is off-screen in a bottom corner of its workspace's display:
  `y = display.maxY - 1`, `x = display.maxX - 1`, or `x = display.x - width + 1` when another display is to the right.
  No visible part of W on any display except the 1pt corner.
- **maximized(W)**: frame = the display's visible frame inset by `gap`.
- **focused(W)**: W is the system's focused window and its app is frontmost.

Wait for the frames to settle (poll until two reads match, max 1 s) after each step: Accessibility moves are async.

### Test config

```toml
gap = 0

[workspaces]
w = 'main'
c = 'main'
x = 'secondary'
s = 'secondary'

[apps.web]                      # one process, windows linked by title
bundle-id = 'dev.foci.probe.a'
title = '^{project} - web$'
workspace = 'w'
launch = 'echo "launch web $FOCI_PROJECT" >> $E2E_LOG; open -na Probe --args --title "{project} - web"'
global-launch = 'echo "global web" >> $E2E_LOG; open -na Probe --args --title "personal - web"'
open-url = 'echo "open-url {url} {project}" >> $E2E_LOG'

[apps.term]                     # one process per project, linked by args
bundle-id = 'dev.foci.probe.b'
args = '--group {project}( |$)'
workspace = 'x'
launch = 'echo "launch term $FOCI_PROJECT" >> $E2E_LOG; open -na ProbeB --args --group {project} --title "{project} term"'

[apps.editor]
bundle-id = 'dev.foci.probe.b'
args = '--group {project}-edit( |$)'
workspace = 'c'
launch = 'echo "launch editor $FOCI_PROJECT {open}" >> $E2E_LOG; open -na ProbeB --args --group {project}-edit'

[apps.chat]                     # unlinked app with a home workspace
bundle-id = 'dev.foci.probe.b'
args = '--group chat( |$)'
workspace = 's'

[apps.dialog]
bundle-id = 'dev.foci.probe.b'
args = '--group dialog( |$)'
floating = true

[apps.notes]                    # new windows join the active project
bundle-id = 'dev.foci.probe.b'
args = '--group notes( |$)'
new-windows = 'active-project'

[apps.ignored]
bundle-id = 'dev.foci.probe.b'
args = '--group ignored( |$)'
manage = false

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

### Standard fixture

Unless a scenario says otherwise: two displays, `main` (landscape, left) and `side` (right; portrait where noted),
active project `alpha`, `w` shown on `main` (focused), `x` shown on `side`, and these windows:

| Name | Started as | Owner | Workspace |
|---|---|---|---|
| `aw` | Probe A `--title 'alpha - web'` | alpha | w |
| `bw` | same Probe A process, window `beta - web` | beta | w |
| `at` | Probe B `--group alpha` | alpha | x |
| `bt` | Probe B `--group beta` | beta | x |
| `ae` | Probe B `--group alpha-edit` | alpha | c |
| `ch` | Probe B `--group chat` | – | s |
| `term0` | the test terminal | – | w |

Scenarios marked **[1D]** run with one display, **[2D]** need two (a second monitor, or a virtual display via
BetterDisplay / `CGVirtualDisplay`), **[manual]** need a person (cables, sleep).

---

## A. Discovery and linking by rules

**A1 Rules link new windows and place them on the app's workspace.** Fresh state, `alpha` active.
Start `aw`, `bw`, `at`, `bt`, `ch`.
Expect: owners and workspaces as in the fixture table; `bw`, `bt` parked; `aw`, `at` shown; `ch` parked (`s` not shown).

**A2 Unmatched window is unlinked on the focused workspace.** Focus `w`, open TextEdit.
Expect: TextEdit `project: null`, `workspace: w`, shown. After `foci project beta` and `foci project --none` it is still shown.

**A3 `manage = false` windows are ignored.** Start Probe B `--group ignored`.
Expect: not in `list-windows`; drag it anywhere and switch projects/workspaces: its frame never changes.

**A4 `floating = true` app.** Start Probe B `--group dialog` at 400x300 in the middle of `main`.
Expect: `floating: true`, frame unchanged (not maximized), not counted as a tile when `w` is in tiles.

**A5 `new-windows = 'active-project'`.** `alpha` active: start `notes`. Expect owner `alpha`.
`foci project --none`, start a second `notes` window. Expect it unlinked.
`foci project beta` (beta doesn't use `notes`), third window. Expect unlinked.

**A6 Renamed window gets linked by a title rule.** In Probe A open `scratch` (unlinked, on `w`). Rename to `beta - web`.
Expect owner `beta`, parked (alpha active).

**A7 Manual unlink beats title rules.** `foci run --window <aw> unlink`, then rename `aw` to `alpha - web` again
(or any title change). Expect still unlinked.

**A8 Closed windows disappear.** Close `bw`. Expect it gone from `list-windows`, `list-projects` beta count −1,
`state.json` no longer has its id. Closing the focused window of a tiled workspace re-tiles the rest (see F11).

**A9 App restart re-links by rules.** `alpha` active, `w` in tiles. Quit Probe B (`at`, `bt`, `ae`, `ch` vanish), relaunch
the same commands. Expect new window IDs with the same owners and workspaces; the old IDs dropped from `state.json`.

---

## B. Projects

**B1 Switch hides other projects on every display; unlinked windows stay.** [2D] `foci project beta`.
Expect `bw`, `bt` shown; `aw`, `at` parked; `term0` shown; focused workspace still `w`; `status.project = beta`.

**B2 No project.** `foci project --none`. Expect every linked window parked, `term0` and unlinked windows on shown
workspaces shown; `status.project = null`.

**B3 Cycle.** From `alpha`: `foci project next` → beta, `next` → alpha (wraps), `prev` → beta.
From none: `next` → alpha (first), `prev` → beta (last).

**B4 Back and forth.** alpha → `project beta` → `project-back-and-forth` → alpha → again → beta.
After `project --none`, back-and-forth returns to the project before it. Fresh state (no previous): exit 0, no change.

**B5 Unknown project.** `foci project nope`: exit 1, stderr `unknown project 'nope'`, nothing moves, state unchanged.

**B6 Same project is a no-op.** `foci project alpha` while alpha active: no frames change, `previousProject` unchanged.

**B7 Focus is restored per project and workspace.** alpha: two windows on `w` (`aw`, `aw2`), focus `aw2`.
`project beta`, focus `bw`. `project alpha` → focused(`aw2`). `project beta` → focused(`bw`).

**B8 Focusing a hidden window follows it.** alpha active on `w`. Activate `bw` from outside Foci: Dock click on
Probe A's window menu, `open -a`, Cmd-Tab, a notification. Expect project → beta, `w` shown, focused(`bw`).
Same for `bt` on `x` (other display): project beta, `x` shown on `side`, focused workspace `x`.

**B9 Stale focus at startup doesn't switch.** Quit Foci with `bw` focused while parked (focus it via `run --window`
then switch away so it stays key), start Foci. Expect project unchanged; `bw` stays parked.

**B10 Autostart on switch, shown workspaces only.** Close `ae`, `project beta`.
With `w` and `x` shown: `foci project alpha` → no launch (`editor` lives on `c`).
`foci 'workspace c; project beta; project alpha'` → one `launch editor alpha "$HOME/src/alpha api"` in `$E2E_LOG`,
not repeated if the switch is repeated within 30 s before the window appears; the new window is linked to alpha on `c`.

**B11 Window from a launch is linked by the pending launch.** Editor def without a matching args rule (start with a
`--group other`): a window appearing ≤30 s after an alpha launch of `editor` is linked to alpha; after 30 s it is not.

**B12 Project removed from config.** Delete `beta` from the config and save (config reloads on save).
Expect `bw`, `bt` unlinked and shown on their workspaces; if beta was active, `status.project = null`.
Add it back: windows are re-linked by rules (`bw` title, `bt` args).

**B13 Layout per project.** alpha: `foci 'workspace w; layout tiles'`. `project beta`: `w` maximized.
`project alpha`: `w` tiles again. `list-workspaces` reports the active project's layout.

---

## C. Workspaces

**C1 Switch changes only its display.** [2D] `foci workspace c`. Expect `ae` shown, `aw`, `term0` parked, `side`
still shows `x` with `at` shown, focused(`ae`), `previousWorkspace = w`.

**C2 Switch to a workspace on the other display moves focus there.** [2D] `foci workspace s`.
Expect `side` shows `s` (`ch` shown, `at` parked), `main` still shows `w`, focused(`ch`), `status.focusedWorkspace = s`.

**C3 Ad hoc workspace.** Focus on `side`, `foci workspace q` (not in config). Expect `q` on `side`, empty,
`at` parked. `foci workspace w`, `foci workspace q`: still on `side`. Persisted in `state.json` `workspaceDisplay`.

**C4 Cycle stays on the display.** [2D] On `main` (`w`, `c`, plus ad hoc ones there, sorted by name):
`workspace next` from `w` wraps to `c`; workspaces of `side` are never picked.

**C5 Back and forth.** `w` → `workspace c` → `workspace-back-and-forth` → `w` → again → `c`. Across displays
(`w` → `s` → back) the focus returns to `main`.

**C6 Empty workspace.** `foci workspace c` with no window there: exit 0, every window of `w` parked, nothing focused
by Foci (the frontmost app keeps focus).

**C7 Autostart on workspace switch.** Close `ae`, `foci workspace c`: one editor launch for alpha. No launch for
`autostart = false` apps (`web`, `term`) when their workspace is empty.

**C8 Parking geometry.** [2D] After C1: `aw` and `term0` parked on `main` in the corner that does not touch `side`
(`x = main.x - width + 1`, since `side` is to the right); `bt` parked on `side` at `x = side.maxX - 1`.
Moving a mouse along the bottom edge never reveals more than 1pt.

**C9 Workspace counts.** `foci list-workspaces --json` lists `w`, `c` on `main` and `x`, `s` on `side`
(plus ad hoc ones), `shown`/`focused` per `status`, `windows` = windows of the active project + unlinked, minus frozen.

---

## D. Moving windows

**D1 Move to a workspace without following.** Focus `aw`, `foci move-to-workspace c`.
Expect `aw` workspace `c`, parked; focused workspace still `w`; focused(`term0`) (best remaining window).

**D2 Move and follow.** `foci move-to-workspace --follow c`. Expect `c` shown, `aw` shown with `ae`, focused(`aw`).

**D3 Move to an ad hoc workspace.** `foci move-to-workspace --follow z`. `z` is created on the focused window's
display and shown there.

**D4 Move to the other display.** [2D] Focus `aw`, `foci move-to-display next`.
Expect `aw` on `x` (the workspace shown on `side`), shown on `side`, focus stays on `main` (`term0`).
With `--follow`: focused workspace `x`, focused(`aw`). `prev` from `main` wraps to `side` too (two displays).

**D5 Move to display with one display.** [1D] `move-to-display next`: exit 0, nothing changes.

**D6 Move a workspace to the other display.** [2D] Focus `w`, `foci move-workspace-to-display next`.
Expect `w` on `side` with `aw`, `term0` maximized there; `x` no longer shown; `main` shows another of its
workspaces (`c`, or the last it showed); persisted. `move-workspace-to-display prev` moves it back; `x` reappears
on `side` (display history).

**D7 Move a workspace off the only workspace of a display.** [2D] Move `x` to `main` while `side` has no other
workspace. Expect `side` shows a new `display-2` workspace.

**D8 Moving a floating window to another display centers it.** [2D] Float `aw` (F8), `move-to-display next`.
Expect `aw` centered on `side`'s visible frame, size clamped to it.

**D9 No focused window.** Focus the desktop (Finder with no windows): `foci move-to-workspace c` → exit 1
`no focused window`. Same for `move-to-display`, `link`, `unlink`, `float`, `resize`.

**D10 Explicit window, even hidden.** `foci run --window <bw> 'move-to-workspace c'` while alpha active:
`bw` moves to `c`, stays parked, alpha's windows untouched. `foci run --window <bw> reveal`: beta active, `c` shown,
focused(`bw`).

---

## E. Focus

**E1 Cycle within the workspace.** `w` has `aw`, `aw2`, `term0` (seq order = creation order). `foci focus next`
three times: each in order, wrapping. `prev` goes back. Windows of beta and parked workspaces are skipped.

**E2 Frozen windows are skipped.** Minimize `aw2`: `focus next` cycles `aw` ↔ `term0`.

**E3 Nothing focused yet.** Focus another display's window, then `focus next` on a workspace: first window gets focus.

**E4 Focus the other display.** [2D] `foci focus-display next`: focused workspace `x`, focused(last focused alpha
window on `x`, else the first). `prev` back to `w` with its last focused window.

---

## F. Layout

**F1 Maximized by default.** Every non-floating shown window = maximized; with `gap = 10`, inset by 10 on all sides.

**F2 Tiles side by side on landscape.** `w` with `aw`, `aw2`, `term0`: `foci layout tiles`.
Expect three equal columns in seq order, gap between and around them, full height of the visible frame.

**F3 Tiles stacked on portrait.** [2D, `side` portrait] `foci 'workspace x; layout tiles'` with two windows: rows.

**F4 Toggle and orientation.** `layout toggle` flips tiles ↔ maximized. `layout toggle-orientation` on
maximized landscape → tiles stacked; again → side by side.

**F5 Move swaps neighbours.** Tiles `[aw, aw2, term0]`, focus `aw`: `move next` → `[aw2, aw, term0]`,
focused(`aw`); `move prev` twice → wraps to the end. Order persists across project switches and restarts.
Floating focused window: exit 1 `no focused tiled window`.

**F6 Resize by points.** Two tiles on a 2560pt-wide display, gap 0: `resize +200` → focused tile 1480, other 1080.
`resize -200` → back to 1280/1280. Repeated `+1000` stops at 95 %; repeated `-1000` at 5 %.
In maximized or with one tile: exit 0, no change.

**F7 Balance.** After F6, `balance` → equal tiles. Weights of other workspaces are untouched.

**F8 Float.** Focus `aw2` in tiles, `foci float`. Expect `aw2` at 70 % of the visible frame, centered (15 % margins),
focused, other tiles re-split. `float` again → back into the tiles at its old position.

**F9 Floating frame is remembered.** Drag the floating `aw2` to a corner, `project beta`, `project alpha`:
`aw2` returns to the dragged frame. Same after `workspace c; workspace w` and a Foci restart.

**F10 User drags of managed windows snap back.** Drag or resize a tiled/maximized window with the mouse,
then any refresh (focus change): it returns to its planned frame.

**F11 Windows coming and going re-tile.** In tiles, open a new alpha `web` window → it joins at the end, tiles
re-split. Close the middle one → the rest fill the space.

**F12 Initial layout from config.** Change `c = 'main'` to `[workspaces.c] display = 'main'` + `layout = 'tiles'`, save:
a project that never set `c` gets tiles; one that did keeps its runtime choice.

---

## G. Manual linking

**G1 Link to another project.** Focus `term0`, `foci link beta`. Expect `term0` owner beta, `manual`, parked
(alpha active), focus moves to the best remaining window of `w`.

**G2 Link to the active project.** Focus TextEdit (unlinked), `foci link --active` → owner alpha, still shown;
`project beta` parks it. With no active project: exit 1 `no active project`.

**G3 Unknown project.** `foci link nope`: exit 1 `unknown project 'nope'`.

**G4 Unlink.** Focus `aw`, `foci unlink`. `aw` stays shown after `project beta` and `project --none`;
renaming it does not re-link it (manual).

**G5 One process, several projects.** `aw` and `bw` belong to the same Probe A process: switching projects parks
one and shows the other, on the same workspace, without hiding the app (no Cmd-H effect, Dock shows it running).

**G6 Manual links don't survive the app's restart.** Link TextEdit to beta, quit and reopen TextEdit
(new window ID): it comes back unlinked (no rule). Document: rules are the durable way to link.

---

## H. Launch

**H1 Focus an existing window.** alpha active on `c`: `foci launch web` → `w` shown, focused(`aw`), no launch logged.

**H2 Launch for the project.** Close every alpha `web` window: `foci launch web` →
`launch web alpha` logged, env `FOCI_PROJECT=alpha`; the new window linked to alpha on `w`. A second
`launch web` within 30 s before the window appears does not launch again.

**H3 Outside the project.** `project --none`: `foci launch web` → focuses the newest unlinked `web` window if any,
else `global web` logged. `launch term` (no global-launch): exit 1.

**H4 Unknown app.** `foci launch nope`: exit 1 `unknown app 'nope'`.

**H5 `{open}` is quoted.** H2 for `editor`: logged path is `"$HOME/src/alpha api"` as one argument.

---

## I. Minimized, hidden, fullscreen

**I1 Minimized windows keep their record and are not moved.** Minimize `aw`: `frozen: true`, owner and workspace
kept. `project beta`, `project alpha`: no frame call on it. Unminimize while beta is active: `aw` is parked on the
next refresh; unminimize while alpha on `w`: shown and laid out.

**I2 App hidden (Cmd-H).** Hide Probe A: `aw`, `bw` frozen. Unhide: each goes back to shown or parked per the rules.

**I3 Native fullscreen.** Fullscreen `aw`: frozen, Foci doesn't touch it, it isn't a tile. Leave fullscreen: laid out again.

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

---

## K. State, quit, CLI

**K1 Persistence across restarts.** After a mix of B–G, `pkill -TERM -x foci`, start again.
Before the restart every window is on screen (restoreAll), maximized/tiled per its workspace's display.
After: same active project, workspaces per display, owners, manual flags, layouts, weights, order, floating
frames; parked windows parked again.

**K2 Quit restores windows.** `pkill -TERM -x foci`: no window remains parked; floating windows at their frames.

**K3 Old state files.** Start with a `state.json` missing newer keys (`layouts`, `seq`, `weight`, `displayHistory`):
loads, defaults applied.

**K4 Scripts.** `foci 'workspace c; layout tiles; workspace w'` runs in order. `foci 'project nope; workspace c'`:
exit 1 with the error, `c` still shown. `foci bogus` → exit 2 before reaching the app. App not running → exit 3.

**K5 Subscribe.** `foci subscribe` emits one status line per project/workspace/display change, none for no-ops
(B6, D5).

**K6 URL router switches projects.** With `bt` focused in a terminal-like Probe, `foci open https://x` from that
process: project beta, `w` shown, `bw` focused, `open-url https://x beta` logged. From `term0` (unlinked): the
active project's web window.

---

## Coverage map

| Command | Scenarios |
|---|---|
| `project <name>/--none/next/prev`, `project-back-and-forth` | B1–B7, B13 |
| `workspace <name>/next/prev`, `workspace-back-and-forth` | C1–C7 |
| `move-to-workspace [--follow]` | D1–D3, D9, D10 |
| `move-to-display [--follow]` | D4, D5, D8 |
| `move-workspace-to-display` | D6, D7 |
| `focus-display`, `focus` | E1–E4 |
| `move`, `layout`, `resize`, `balance`, `float` | F2–F9 |
| `link`, `unlink` | G1–G6, A7 |
| `reveal`, `run --window` | D10 |
| `launch`, autostart | H1–H5, B10, B11, C7 |
| `reload-config` | B12, F12 |
| OS events (focus, rename, close, minimize, hide, fullscreen, displays, app restart) | A6–A9, B8, B9, I1–I4, J1–J5 |

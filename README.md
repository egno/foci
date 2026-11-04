# Foci

A small macOS window manager for working on one project at a time, keyboard first.

- **Projects.** A window is either *linked* to one project or *unlinked*. Switching projects shows the target
  project's windows where they were and hides other projects' windows on all displays. Each project gets back
  the workspace it last showed on each display, the focused workspace and the window in front. Unlinked windows
  are never touched by project switching.
- **Workspaces**, AeroSpace style. Every letter is a workspace. Each one lives on one display, and each display
  shows one workspace at a time. Workspace names are shared by all projects: `w` is "web" in every project and
  shows only the active project's browser windows (plus unlinked ones). Displays are followed as they come and
  go: a reconnected display shows its last workspace again, and the focused workspace follows its windows off a
  disconnected one. Displays are called `built-in` (the laptop's screen) and `ext 1`…`ext N` (the others, from the
  left), in the menu, the CLI and the config; the model name (`dell`) works too. They are numbered from the left
  (then top to bottom), or in the order of `display-order = ['built-in', 'ext 2', 'ext 1']` (unlisted ones follow),
  the same order everywhere: the menu bar, `1`–`3` after the leader, `focus-display 2`, `next|prev`, `x = '2'` in
  `[workspaces]`. Display commands take `next|prev` (wrapping), `left|right|up|down` (the nearest display on that
  side), a number, `main`, a name (`ext 2`) or part of the model name.
- **Maximized by default, tiles on demand.** Each workspace is `maximized` (windows fill the display as an
  accordion, like AeroSpace's: the edges of the windows behind the focused one show at its left and right, also on portrait displays,
  `accordion-padding` points, 30; `focus next|prev` cycles) or `tiles` (side by side on landscape, stacked on portrait; `move`, `resize`, `balance`). The layout is
  remembered per project and workspace. `float` takes a window out of the layout.
- **Linking.** Rules over bundle ID, process arguments (`--user-data-dir`, `--instance-group`) and window title
  link windows automatically and re-link them after app restarts. `link <project>` / `unlink` override the rules
  by hand.
- **URL router.** Make Foci the default browser and a link opens in the browser of the project it was clicked
  in: the project's first app with `open-url`, in its last focused window. The opener is the app that sent the
  link, or the nearest parent process with windows (a terminal running `open`, `gh --web`). Links from unlinked
  windows go to the active project. Outside any project, `browser` opens them in an unlinked window.
- **Leader key and submenus**, like AstroNvim. The leader (`leader = ['right-cmd', 'f20', 'ctrl-esc']`: right ⌘
  tapped alone, or a key; `hold-space`: space held for `hold-delay` ms (250), typed as usual when tapped or
  when the next key comes first) opens a menu of single plain keys:

  | Key | Does |
  |---|---|
  | `a`–`z` | workspace |
  | leader | last workspace |
  | arrows | focus |
  | `enter` | next window of the focused app (active project and unlinked, any workspace; repeats) |
  | `tab` | next display |
  | `1`–`3` | display by number, from the left |
  | `space` | +project: the same keys for projects (a project's key, `space` last project, `.` move window, `,` go with window, `n` no project, arrows cycle) |
  | `.` | +move (arrows, `tab` window to next display, `1`–`3` to that display, `space` workspace to next display) |
  | `,` | +go with window (also `tab`, `1`–`3`) |
  | `/` | +launch: launch or focus the active project's window of an app, keyed by its workspace |
  | `'` | +layout (`enter` toggle) |
  | `;` | +config (`r` reload, `e` edit) |

  In binding keys `leader` stands for all the leader keys, `{workspace}` for every letter
  (`'{workspace}' = 'workspace {workspace}'`) and `{project}` for each project's key: the first letter of its
  name, or `key = '...'` in its `[[projects]]` (`'{project}' = 'project {project}'`). Modes other than `main` are one-shot: a key acts and Foci returns
  to `main`, unless the key enters another mode or the mode is `sticky = true`. In every submenu `esc` closes and
  `backspace` goes up one level. A submenu also closes after `leader-timeout` ms (5000), on a click, and on a key
  it doesn't bind (the key still reaches the app).
- **Repeat keys**, like Emacs's repeat-mode: after a key with `repeat = true` acts (focus, move, resize), only
  the repeat keys of its mode stay bound for `repeat-timeout` ms (1000), so `leader → → →`. Any other key
  goes to the app.
- **Key hints**, like which-key: if no key is pressed for `key-hints-delay` ms (300), a popup at the bottom
  of the focused display lists the next keys, titled with the path (`Foci › Move`). Submenus show as
  `+label`. Keys that do the same with their own key show as one row: `a-z → workspace`. Name things with
  `[mode.<name>] label = '...'` and `key = { run = '...', label = '...' }`.
- **Menu bar**, like AeroSpace's experimental UI: the project, the workspace shown on each display (left to right) as a
  lettered square (focused one filled), hidden workspaces with windows dimmed, and the mode while in a
  submenu. `menu-bar-style = 'i3' | 'squares' | 'text'`. The menu lists projects, one submenu of workspaces per
  display, the layout of the focused workspace and the windows. ⌘-drag the item where you want it; the place sticks
  across launches.
- **Autostart.** When you switch to a workspace and the active project has no window of an app that belongs
  there, Foci launches it (per app, configurable). `launch <app>` does the same on demand, or focuses the window
  if there is one. A project's `open` items (`{ app = 'cursor', open = ['~/src/bil'] }`) are substituted, quoted,
  into the app's `{open}`.

Hidden windows are parked off-screen in a bottom corner of their display, one window at a time (like AeroSpace):
the corner that doesn't reach into another display. The middle one of three displays in a row has no such corner,
so its windows park in the free outer corner of a neighbour.
This lets windows of one process (one Chrome) belong to different projects. On quit Foci puts every window
back on screen.

## Install

Download `Foci-<version>.dmg` from [Releases](https://github.com/egno/foci/releases) (macOS 14+, Apple silicon and
Intel), open it and drag `Foci.app` onto Applications (or unzip `Foci-<version>.zip`). The app isn't notarized, so
macOS blocks it at first; clear the quarantine flag once and open it:

```sh
xattr -dr com.apple.quarantine /Applications/Foci.app
open /Applications/Foci.app
ln -sf /Applications/Foci.app/Contents/MacOS/foci ~/.local/bin/foci   # optional: the CLI
```

Foci asks for the Accessibility permission on first start. Release builds are signed ad hoc, so after updating to
a new version macOS may ask again: remove Foci from System Settings → Privacy & Security → Accessibility and add
it back.

## Build & run

Requires macOS 14+, Swift 6.

```sh
scripts/make-signing-cert.sh   # once: a stable signature keeps the Accessibility permission across rebuilds
make test
make install                   # builds build/Foci.app, installs to ~/Applications, starts it
make log                       # follow the log
make release                   # build/Foci-<version>.dmg and .zip for a GitHub release (universal, ad hoc signed)
```

With `start-at-login = true` (the default config) Foci registers itself as a login item; macOS may ask you to allow
it in System Settings → General → Login Items.

To route links, pick Foci in System Settings → Desktop & Dock → Default web browser.

On first start Foci asks for the Accessibility permission and writes an example config to
`~/.config/foci/config.toml`. The config is reloaded on save; problems appear in the menu bar menu (⚠).
State (links, active project and workspaces) is kept in `~/Library/Application Support/Foci/state.json`.
For tests, `FOCI_HOME=<dir>` moves the config (`config.toml`), the state and the CLI socket into `<dir>`.

Don't run Foci and another tiling window manager (AeroSpace, yabai) at the same time.

## CLI

`make install` links `~/.local/bin/foci` to the app binary. With arguments it talks to the running app over
`~/Library/Application Support/Foci/foci.sock`:

```sh
foci project bil                     # any command script, same syntax as key bindings
foci 'workspace w; layout tiles'
foci run --window 12055 'link iam'   # target a window by ID instead of the focused one
foci open https://example.com        # open a link in this terminal's project browser (BROWSER='foci open')
foci status [--json]
foci list-windows [--json] [--project bil | --unlinked | --active] [--workspace w] [--visible] [--pid 123]
foci list-workspaces [--json]          # displays left to right, as numbered
foci list-projects [--json]
foci subscribe                       # one JSON status line per change, e.g. for sketchybar
```

Exit codes: 0 ok, 1 command failed, 2 usage error, 3 app not running.

## Code layout

| Target | Contents |
|---|---|
| `FociCore` | Domain and application logic, no AppKit: model, config types, commands, link rules (`Linker`), layout (`Planner`), `Engine`, ports (`WindowSystem`, `Launcher`, `StateStore`, `ConfigSource`). |
| `FociMac` | Adapters: Accessibility (`AXWindowSystem`), Carbon hotkeys, TOML config, JSON state, shell launcher, menu bar, `FociApp` (wiring). |
| `foci` | Executable: single-instance lock, starts `FociApp`. |

Core tests run the engine against in-memory fakes (`Tests/FociCoreTests/Fakes.swift`); `Tests/FociMacTests` checks
the TOML config. `Tests/E2E` holds end-to-end scenarios against real windows (`SCENARIOS.md` is the spec, `make e2e`
runs them with a fixture app and its own `FOCI_HOME`; it stops your Foci meanwhile).

## Roadmap

1. **M1:** projects, workspaces on 2 displays, maximized layout, link rules + manual linking, autostart,
   hotkey modes, menu bar, state persistence.
2. **M2:** tiling layout per project+workspace, move, resize, balance.
3. **M3:** `foci` CLI over a Unix socket, `subscribe` for status bars.
4. **M4:** URL router: open links in the opener project's browser window.
5. **M5:** leader key with submenus, key hints, repeat keys; displays connected and disconnected at runtime.

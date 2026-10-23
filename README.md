# Foci

A small macOS window manager for working on one project at a time, keyboard first.

- **Projects.** A window is either *linked* to one project or *unlinked*. Switching projects shows the target
  project's windows where they were and hides other projects' windows on all displays. Unlinked windows are never
  touched by project switching.
- **Workspaces**, AeroSpace style. Every workspace lives on one display, and each display shows one workspace at a
  time. Workspace names are shared by all projects: `w` is "web" in every project and shows only the active
  project's browser windows (plus unlinked ones).
- **Maximized by default, tiles on demand.** Each workspace is `maximized` (windows fill the display, `focus next|prev`
  cycles) or `tiles` (side by side on landscape, stacked on portrait; `move`, `resize`, `balance`). The layout is
  remembered per project and workspace. `float` takes a window out of the layout.
- **Linking.** Rules over bundle ID, process arguments (`--user-data-dir`, `--instance-group`) and window title
  link windows automatically and re-link them after app restarts. `link <project>` / `unlink` override the rules
  by hand.
- **URL router.** Make Foci the default browser and a link opens in the browser of the project it was clicked
  in: the project's first app with `open-url`, in its last focused window. The opener is the app that sent the
  link, or the nearest parent process with windows (a terminal running `open`, `gh --web`). Links from unlinked
  windows go to the active project. Outside any project, `browser` opens them in an unlinked window.
- **Leader key and submenus**, like AstroNvim. The leader (`f20` / `ctrl-esc`) opens a menu of single
  plain keys: focus, and submenus `w` workspace, `space` project, `m` move, `g` go with window, `e` layout, `l` link,
  `;` config. Modes other than `main` are one-shot: a key acts and Foci returns to `main`, unless the key
  enters another mode or the mode is `sticky = true` (resize). In every submenu `esc` closes and
  `backspace` goes up one level.
- **Key hints**, like which-key: if no key is pressed for `key-hints-delay` ms (200), a popup at the bottom
  of the focused display lists the next keys, titled with the path (`Foci › Move`). Submenus show as
  `+label`. Name things with `[mode.<name>] label = '...'` and `key = { run = '...', label = '...' }`.
- **Autostart.** When you switch to a workspace and the active project has no window of an app that belongs
  there, Foci launches it (per app, configurable).

Hidden windows are parked off-screen in a bottom corner of their display, one window at a time (like AeroSpace).
This lets windows of one process (one Chrome) belong to different projects. On quit Foci puts every window
back on screen.

## Build & run

Requires macOS 14+, Swift 6.

```sh
scripts/make-signing-cert.sh   # once: a stable signature keeps the Accessibility permission across rebuilds
make test
make install                   # builds build/Foci.app, installs to ~/Applications, starts it
make log                       # follow the log
```

With `start-at-login = true` (the default config) Foci registers itself as a login item; macOS may ask you to allow
it in System Settings → General → Login Items.

To route links, pick Foci in System Settings → Desktop & Dock → Default web browser.

On first start Foci asks for the Accessibility permission and writes an example config to
`~/.config/foci/config.toml`. The config is reloaded on save; problems appear in the menu bar menu (⚠).
State (links, active project and workspaces) is kept in `~/Library/Application Support/Foci/state.json`.

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
foci list-workspaces [--json]
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

Core tests run the engine against in-memory fakes (`Tests/FociCoreTests/Fakes.swift`).

## Roadmap

1. **M1:** projects, workspaces on 2 displays, maximized layout, link rules + manual linking, autostart,
   hotkey modes, menu bar, state persistence.
2. **M2:** tiling layout per project+workspace, move, resize, balance.
3. **M3:** `foci` CLI over a Unix socket, `subscribe` for status bars.
4. **M4:** URL router: open links in the opener project's browser window.

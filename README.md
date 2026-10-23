# Foci

A small macOS window manager for working on one project at a time, keyboard first.

- **Projects.** A window is either *linked* to one project or *unlinked*. Switching projects shows the target
  project's windows where they were and hides other projects' windows on all displays. Unlinked windows are never
  touched by project switching.
- **Workspaces**, AeroSpace style. Every workspace lives on one display, and each display shows one workspace at a
  time. Workspace names are shared by all projects: `w` is "web" in every project and shows only the active
  project's browser windows (plus unlinked ones).
- **Maximized by default.** Windows fill their display. `focus next|prev` cycles through them; `float` toggles a
  window out of the layout.
- **Linking.** Rules over bundle ID, process arguments (`--user-data-dir`, `--instance-group`) and window title
  link windows automatically and re-link them after app restarts. `link <project>` / `unlink` override the rules
  by hand.
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

On first start Foci asks for the Accessibility permission and writes an example config to
`~/.config/foci/config.toml`. The config is reloaded on save; problems appear in the menu bar menu (⚠).
State (links, active project and workspaces) is kept in `~/Library/Application Support/Foci/state.json`.

Don't run Foci and another tiling window manager (AeroSpace, yabai) at the same time.

## Code layout

| Target | Contents |
|---|---|
| `FociCore` | Domain and application logic, no AppKit: model, config types, commands, link rules (`Linker`), layout (`Planner`), `Engine`, ports (`WindowSystem`, `Launcher`, `StateStore`, `ConfigSource`). |
| `FociMac` | Adapters: Accessibility (`AXWindowSystem`), Carbon hotkeys, TOML config, JSON state, shell launcher, menu bar, `FociApp` (wiring). |
| `foci` | Executable: single-instance lock, starts `FociApp`. |

Core tests run the engine against in-memory fakes (`Tests/FociCoreTests/Fakes.swift`).

## Roadmap

1. **M1 (this):** projects, workspaces on 2 displays, maximized layout, link rules + manual linking, autostart,
   hotkey modes, menu bar, state persistence.
2. Tiling layout per workspace (`layout tiles|maximized`), resize.
3. `foci` CLI over a Unix socket (`foci run 'project bil'`, `foci list-windows`), events for sketchybar.
4. URL router: open links in the opener project's browser window.

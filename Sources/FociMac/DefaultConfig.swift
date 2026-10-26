/// Written to `~/.config/foci/config.toml` on first start.
enum DefaultConfig {
    static let text = #"""
        # Foci config. Reloaded automatically when saved.
        #
        # Model:
        # - A window is either linked to one project or unlinked. Unlinked windows are never touched by project
        #   switching. Link rules below link windows automatically; `link <project>` / `unlink` override them.
        # - Every workspace lives on one display. Each display shows one workspace at a time.
        # - On screen: windows of each display's workspace that are unlinked or linked to the active project.
        #   Everything else is parked off-screen.

        start-at-login = true

        # Menu bar label, after AeroSpace's experimental UI:
        # 'i3'       mode (circled letter), project, workspace shown on each display (focused one filled), plus the
        #            hidden workspaces that have windows in the active project, dimmed
        # 'squares'  only the shown workspaces
        # 'text'     BIL · [w] x
        menu-bar-style = 'squares'

        gap = 0

        # Maximized windows are an accordion: the focused one leaves this many points at each side, where the
        # edges of the windows behind it show. 0 = every window fills the display.
        accordion-padding = 30

        # 'maximized': every window fills the display (an accordion, see 'accordion-padding'), 'focus next|prev'
        # cycles through them.
        # 'tiles': windows side by side (landscape) or stacked (portrait). 'layout ...' commands change the layout
        # of the focused workspace for the active project only; Foci remembers it.
        default-layout = 'maximized'

        # Key hints, like which-key in AstroNvim: in any mode but 'main' (after the leader key), a popup lists
        # the next keys when no key is pressed for 'key-hints-delay' milliseconds. Keys that only switch to
        # another mode are groups, shown as '+label' of that mode.
        key-hints = true
        key-hints-delay = 300

        # A submenu closes after 'leader-timeout' milliseconds without a key (0 = never), on a click, and on a
        # key it doesn't bind (that key still reaches the app).
        leader-timeout = 5000
        # Repeat keys ('repeat = true', like Emacs's repeat-mode): after one acts, only the repeat keys of its
        # mode stay bound for 'repeat-timeout' milliseconds, so 'leader → → →'. Any other key goes to the app.
        repeat-timeout = 1000

        # The leader: any of these keys. In bindings, 'leader' stands for all of them.
        # Tapped alone (right-cmd, left-alt, ...): still a modifier when held with another key.
        leader = ['right-cmd', 'f20', 'ctrl-esc']

        # URL router: make Foci the default browser (System Settings > Desktop & Dock > Default web browser) and
        # links open in the browser of the project they were clicked in: the project's first app with 'open-url'.
        # A link from an unlinked window (Slack) goes to the active project. 'browser' opens links when that
        # project has no browser, or there is no active project, using its 'global-open-url'.
        browser = 'chrome'

        # Workspace -> display: 'main' (menu bar), 'secondary', 1-based index from the left, or part of the name.
        # Long form: x = { display = 'secondary', layout = 'tiles', orientation = 'vertical' }
        # Workspaces not listed here live on the display where they were first used.
        [workspaces]
        a = 'main'
        c = 'main'
        d = 'main'
        f = 'main'
        r = 'main'
        t = 'main'
        v = 'main'
        w = 'main'
        o = 'secondary'
        s = 'secondary'
        x = 'secondary'

        # ---------------------------------------------------------------- Apps
        # bundle-id      which app
        # args / title   regexes over the process command line / window title. {project} = project name.
        #                With {project}: windows that match link to that project.
        # workspace      where new windows of the app go
        # launch         shell command (login shell) starting the app for a project; {project}, and {open} = the
        #                project's 'open' items, quoted ({ app = 'cursor', open = ['~/src/bil'] })
        # global-launch  shell command starting the app when no project uses it
        # open-url       shell command opening a link for a project; {url} (already quoted), {project}.
        #                Foci focuses the project's window of the app first, so the tab opens there. Without a
        #                window, Foci runs 'launch' with the link appended. Name the app ('open -a ...'):
        #                a bare 'open {url}' would send the link back to Foci.
        # global-open-url  the same outside any project, see 'browser'
        # new-windows    'unlinked' (default) or 'active-project': new windows matching no rule
        #                join the active project if it uses this app
        # floating       don't maximize
        # manage         false = ignore the app completely

        # One shared Chrome; each window belongs to a project. Name a window with Chrome's "Name Window..."
        # to keep the link across Chrome restarts (title becomes '<project> - Google Chrome').
        [apps.chrome]
        bundle-id = 'com.google.Chrome'
        title = '^{project} - Google Chrome$'
        workspace = 'w'
        new-windows = 'active-project'
        launch = 'open -na "Google Chrome" --args --new-window'
        global-launch = 'open -na "Google Chrome" --args --new-window'
        open-url = 'open -a "Google Chrome" {url}'
        global-open-url = 'open -a "Google Chrome" {url}'

        # One kitty process per project, attached to the Herdr session of the same name.
        [apps.kitty]
        bundle-id = 'net.kovidgoyal.kitty'
        args = '--instance-group[= ]{project}( |$)'
        workspace = 'x'
        launch = '/Applications/kitty.app/Contents/MacOS/kitty --single-instance --instance-group {project} --directory "$HOME" herdr --session {project}'
        global-launch = 'open -na kitty'

        # One Cursor instance per project. Use the CLI, not 'open -na', to reuse a running instance.
        [apps.cursor]
        bundle-id = 'com.todesktop.230313mzl4w4u92'
        args = '--user-data-dir[= ].*/\.cursor-projects/{project}( |$)'
        workspace = 'c'
        launch = 'cursor --user-data-dir "$HOME/.cursor-projects/{project}"'
        global-launch = 'open -na Cursor'

        [apps.dbeaver]
        bundle-id = 'org.jkiss.dbeaver.core.product'
        args = '-data .*/\.dbeaver-projects/{project}( |$)'
        workspace = 'd'
        launch = 'open -na DBeaver --args -data "$HOME/.dbeaver-projects/{project}"'
        global-launch = 'open -na DBeaver'

        # No {project}: every Firefox window belongs to the one project that uses it, so no global-launch.
        [apps.firefox]
        bundle-id = 'org.mozilla.firefox'
        workspace = 'f'
        launch = 'open -a Firefox'
        open-url = 'open -a Firefox {url}'

        # Global apps: used by no project, so always unlinked. Listed only to place them on a workspace.
        [apps.slack]
        bundle-id = 'com.tinyspeck.slackmacgap'
        workspace = 's'

        [apps.teams]
        bundle-id = 'com.microsoft.teams2'
        workspace = 't'

        [apps.outlook]
        bundle-id = 'com.microsoft.Outlook'
        workspace = 'r'

        [apps.vscode]
        bundle-id = 'com.microsoft.VSCode'
        workspace = 'v'

        [apps.settings]
        bundle-id = 'com.apple.systempreferences'
        workspace = 'a'
        floating = true

        # ---------------------------------------------------------------- Projects
        # Order = 'project next|prev' order.
        # autostart (default true): when you switch to the app's workspace in this project and the project has
        # no window of the app, launch it.
        # key (default: the first letter of the name): what '{project}' in a binding key stands for.
        [[projects]]
        name = 'p'
        apps = ['firefox', { app = 'cursor', autostart = false }, { app = 'kitty', autostart = false }]

        [[projects]]
        name = 'bil'
        apps = ['chrome', 'cursor', 'kitty', { app = 'dbeaver', autostart = false }]

        [[projects]]
        name = 'iam'
        apps = ['chrome', 'cursor', 'kitty', { app = 'dbeaver', autostart = false }]

        [[projects]]
        name = 'gc'
        apps = ['chrome', { app = 'cursor', autostart = false }]

        # ---------------------------------------------------------------- Bindings
        # Commands (separate with ';'):
        #   project <name>|--none|next|prev    project-back-and-forth
        #   workspace <name>|next|prev         workspace-back-and-forth
        #   move-to-workspace [--follow] <name>
        #   move-to-display [--follow] next|prev   the focused window to the other display's workspace
        #   move-workspace-to-display next|prev    focus-display next|prev
        #   focus next|prev                    cycle windows of the focused workspace
        #   move next|prev                     swap the focused window with its neighbour (tile order)
        #   layout tiles|maximized|toggle|toggle-orientation
        #   resize +N|-N (points)    balance
        #   link [--follow] <project>|--active    unlink [--follow]  float (toggle)
        #   launch <app>       focus the active project's window of the app, or launch it
        #   mode <name>    reload-config    exec <shell command>
        #
        # A binding is a script, an array of commands, or
        # { run = <script or array>, label = 'shown in key hints', repeat = true (see 'repeat-timeout') }.
        # In a key, 'leader' stands for every leader key, and '{workspace}' for every letter a-z and any other
        # one-character workspace in [workspaces] ('{workspace}' in its script and label is replaced too). A key
        # bound by name wins. '{project}' stands for each project's key, and for its name in the script and label;
        # a project key that is also bound by name is an error (set 'key' in its [[projects]]).
        #
        # Modes other than 'main' are submenus, like the leader key in AstroNvim: one key acts, then Foci returns to
        # 'main', unless the key enters another mode or the mode is 'sticky = true'. In every submenu 'esc' closes
        # and 'backspace' goes up one level, unless bound. [mode.<name>] label = '...' names the submenu in key hints.

        # Global hotkeys need a modifier, an F-key or a modifier tapped alone; after the leader, single plain keys.
        [mode.main.binding]
        leader = 'mode control'

        [mode.control]
        label = 'Foci'

        [mode.control.binding]
        # Every letter is a workspace, right after the leader.
        '{workspace}' = 'workspace {workspace}'

        space = 'mode project'

        # Leader twice: the last workspace.
        leader = 'workspace-back-and-forth'
        enter = 'layout toggle'
        tab = 'focus-display next'

        # Window order is one row (tiles side by side) or one column (stacked/maximized). Letters are workspaces,
        # so focus is on the arrows.
        right = { run = 'focus next', repeat = true }
        down = { run = 'focus next', repeat = true }
        left = { run = 'focus prev', repeat = true }
        up = { run = 'focus prev', repeat = true }
        minus = { run = 'resize -50', repeat = true }
        equal = { run = 'resize +50', repeat = true }

        period = 'mode move'
        comma = 'mode go'
        slash = 'mode layout'
        # '~' is shift-backtick (one key with '|' on some keyboards).
        shift-backtick = 'mode launch'
        semicolon = 'mode config'

        # Like the workspaces after the leader: a project's key switches to it, space twice the last project,
        # '.' moves the window to a project, ',' goes there with it; arrows cycle.
        [mode.project]
        label = 'Project'

        [mode.project.binding]
        '{project}' = 'project {project}'
        n = { run = 'project --none', label = 'no project' }
        space = { run = 'project-back-and-forth', label = 'last project' }
        period = 'mode link'
        comma = 'mode link-go'
        right = { run = 'project next', repeat = true }
        down = { run = 'project next', repeat = true }
        left = { run = 'project prev', repeat = true }
        up = { run = 'project prev', repeat = true }

        [mode.move]
        label = 'Move'

        [mode.move.binding]
        '{workspace}' = 'move-to-workspace {workspace}'
        right = { run = 'move next', repeat = true }
        down = { run = 'move next', repeat = true }
        left = { run = 'move prev', repeat = true }
        up = { run = 'move prev', repeat = true }
        tab = { run = 'move-to-display next', label = 'to next display' }
        space = { run = 'move-workspace-to-display next', label = 'workspace to next display' }

        [mode.go]
        label = 'Go with window'

        [mode.go.binding]
        '{workspace}' = 'move-to-workspace --follow {workspace}'
        tab = { run = 'move-to-display --follow next', label = 'to next display' }

        [mode.layout]
        label = 'Layout'

        [mode.layout.binding]
        e = 'layout toggle'
        t = 'layout tiles'
        m = 'layout maximized'
        o = 'layout toggle-orientation'
        b = 'balance'
        f = 'float'

        # Link the focused window by hand.
        [mode.link]
        label = 'Move'

        [mode.link.binding]
        '{project}' = 'link {project}'
        l = { run = 'link --active', label = 'link to the active project' }
        n = 'unlink'

        # Link the focused window to a project and switch to it with the window.
        [mode.link-go]
        label = 'Go with window'

        [mode.link-go.binding]
        '{project}' = 'link --follow {project}'
        n = { run = 'unlink --follow', label = 'unlink, no project' }

        # Launch, or focus, the active project's window of an app: the key is the app's workspace.
        [mode.launch]
        label = 'Launch'

        [mode.launch.binding]
        w = 'launch chrome'
        c = 'launch cursor'
        x = 'launch kitty'
        d = 'launch dbeaver'
        f = 'launch firefox'

        [mode.config]
        label = 'Config'

        [mode.config.binding]
        r = 'reload-config'
        e = { run = 'exec open -t ~/.config/foci/config.toml', label = 'edit config' }
        """#
}

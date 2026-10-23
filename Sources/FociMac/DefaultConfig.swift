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

        # 'maximized': every window fills the display, 'focus next|prev' cycles through them.
        # 'tiles': windows side by side (landscape) or stacked (portrait). 'layout ...' commands change the layout
        # of the focused workspace for the active project only; Foci remembers it.
        default-layout = 'maximized'

        # Key hints, like which-key in AstroNvim: in any mode but 'main' (after the leader key), a popup lists
        # the next keys when no key is pressed for 'key-hints-delay' milliseconds. Keys that only switch to
        # another mode are groups, shown as '+label' of that mode.
        key-hints = true
        key-hints-delay = 200

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
        p = 'main'
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
        # launch         shell command (login shell) starting the app for a project; {project}, {open}
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
        launch = 'cursor --user-data-dir "$HOME/.cursor-projects/{project}" {open}'
        global-launch = 'open -na Cursor'

        [apps.dbeaver]
        bundle-id = 'org.jkiss.dbeaver.core.product'
        args = '-data .*/\.dbeaver-projects/{project}( |$)'
        workspace = 'd'
        launch = 'open -na DBeaver --args -data "$HOME/.dbeaver-projects/{project}"'
        global-launch = 'open -a DBeaver'

        # No {project}: every Firefox window belongs to the one project that uses it.
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
        #   move-workspace-to-display next|prev    focus-display next|prev
        #   focus next|prev                    cycle windows of the focused workspace
        #   move next|prev                     swap the focused window with its neighbour (tile order)
        #   layout tiles|maximized|toggle|toggle-orientation
        #   resize +N|-N (points)    balance
        #   link <project>|--active    unlink  float (toggle)
        #   launch <app>       focus the active project's window of the app, or launch it
        #   mode <name>    reload-config    exec <shell command>
        #
        # A binding is a script, an array of commands, or { run = <script or array>, label = 'shown in key hints' }.
        #
        # Modes other than 'main' are submenus, like the leader key in AstroNvim: one key acts, then Foci returns to
        # 'main', unless the key enters another mode or the mode is 'sticky = true'. In every submenu 'esc' closes
        # and 'backspace' goes up one level, unless bound. [mode.<name>] label = '...' names the submenu in key hints.

        # Global hotkeys need a modifier or an F-key; everything after the leader is a single plain key.
        [mode.main.binding]
        f20 = 'mode control'
        ctrl-esc = 'mode control'

        [mode.control]
        label = 'Foci'

        [mode.control.binding]
        space = 'mode project'
        w = 'mode workspace'
        backtick = 'project-back-and-forth'

        enter = 'workspace-back-and-forth'
        f20 = 'workspace-back-and-forth'
        tab = 'focus-display next'

        # Window order is one row (tiles side by side) or one column (stacked/maximized).
        j = 'focus next'
        k = 'focus prev'
        right = 'focus next'
        down = 'focus next'
        left = 'focus prev'
        up = 'focus prev'
        minus = 'resize -50; mode resize'
        equal = 'resize +50; mode resize'

        m = 'mode move'
        g = 'mode go'
        e = 'mode layout'
        l = 'mode link'
        semicolon = 'mode foci'

        # Projects by first letter; space space toggles the last two.
        [mode.project]
        label = 'Project'

        [mode.project.binding]
        p = 'project p'
        b = 'project bil'
        i = 'project iam'
        g = 'project gc'
        n = { run = 'project --none', label = 'no project' }
        space = 'project-back-and-forth'

        # Workspaces by name; space toggles the last two.
        [mode.workspace]
        label = 'Workspace'

        [mode.workspace.binding]
        a = 'workspace a'
        c = 'workspace c'
        d = 'workspace d'
        f = 'workspace f'
        o = 'workspace o'
        p = 'workspace p'
        r = 'workspace r'
        s = 'workspace s'
        t = 'workspace t'
        v = 'workspace v'
        w = 'workspace w'
        x = 'workspace x'
        space = 'workspace-back-and-forth'

        [mode.move]
        label = 'Move'

        [mode.move.binding]
        a = 'move-to-workspace a'
        c = 'move-to-workspace c'
        d = 'move-to-workspace d'
        f = 'move-to-workspace f'
        o = 'move-to-workspace o'
        p = 'move-to-workspace p'
        r = 'move-to-workspace r'
        s = 'move-to-workspace s'
        t = 'move-to-workspace t'
        v = 'move-to-workspace v'
        w = 'move-to-workspace w'
        x = 'move-to-workspace x'
        j = 'move next'
        k = 'move prev'
        right = 'move next'
        down = 'move next'
        left = 'move prev'
        up = 'move prev'
        tab = { run = 'move-workspace-to-display next', label = 'workspace to next display' }

        [mode.go]
        label = 'Go with window'

        [mode.go.binding]
        a = 'move-to-workspace --follow a'
        c = 'move-to-workspace --follow c'
        d = 'move-to-workspace --follow d'
        f = 'move-to-workspace --follow f'
        o = 'move-to-workspace --follow o'
        p = 'move-to-workspace --follow p'
        r = 'move-to-workspace --follow r'
        s = 'move-to-workspace --follow s'
        t = 'move-to-workspace --follow t'
        v = 'move-to-workspace --follow v'
        w = 'move-to-workspace --follow w'
        x = 'move-to-workspace --follow x'

        [mode.layout]
        label = 'Layout'

        [mode.layout.binding]
        e = 'layout toggle'
        t = 'layout tiles'
        m = 'layout maximized'
        o = 'layout toggle-orientation'
        b = 'balance'
        f = 'float'

        # Sticky: repeat - and =, leave with esc.
        [mode.resize]
        label = 'Resize'
        sticky = true

        [mode.resize.binding]
        minus = 'resize -50'
        equal = 'resize +50'
        b = 'balance'

        # Link the focused window by hand.
        [mode.link]
        label = 'Link window'

        [mode.link.binding]
        p = 'link p'
        b = 'link bil'
        i = 'link iam'
        g = 'link gc'
        l = { run = 'link --active', label = 'link to the active project' }
        u = 'unlink'

        [mode.foci]
        label = 'Config'

        [mode.foci.binding]
        r = 'reload-config'
        e = { run = 'exec open -t ~/.config/foci/config.toml', label = 'edit config' }
        """#
}

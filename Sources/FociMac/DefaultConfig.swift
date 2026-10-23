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
        gap = 0

        # 'maximized': every window fills the display, 'focus next|prev' cycles through them.
        # 'tiles': windows side by side (landscape) or stacked (portrait). 'layout ...' commands change the layout
        # of the focused workspace for the active project only; Foci remembers it.
        default-layout = 'maximized'

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

        [mode.main.binding]
        f20 = 'mode control'
        ctrl-esc = 'mode control'

        # Leader mode: one key acts, then back to main.
        [mode.control.binding]
        esc = 'mode main'

        1 = 'project p; mode main'
        2 = 'project bil; mode main'
        3 = 'project iam; mode main'
        4 = 'project gc; mode main'
        0 = 'project --none; mode main'
        backtick = 'project-back-and-forth; mode main'
        slash = 'mode project'

        # Window order is one row (tiles side by side) or one column (stacked/maximized):
        # left/up = previous, right/down = next.
        left = 'focus prev; mode main'
        up = 'focus prev; mode main'
        right = 'focus next; mode main'
        down = 'focus next; mode main'
        space = 'focus next; mode main'
        shift-left = 'move prev; mode main'
        shift-up = 'move prev; mode main'
        shift-right = 'move next; mode main'
        shift-down = 'move next; mode main'
        z = 'float; mode main'
        e = 'layout toggle; mode main'
        shift-e = 'layout toggle-orientation; mode main'
        b = 'balance; mode main'
        # Stay in control mode to repeat: minus minus minus esc
        minus = 'resize -50'
        equal = 'resize +50'

        m = 'focus-display next; mode main'
        tab = 'move-workspace-to-display next; mode main'
        f20 = 'workspace-back-and-forth; mode main'

        a = 'workspace a; mode main'
        c = 'workspace c; mode main'
        d = 'workspace d; mode main'
        f = 'workspace f; mode main'
        o = 'workspace o; mode main'
        p = 'workspace p; mode main'
        r = 'workspace r; mode main'
        s = 'workspace s; mode main'
        t = 'workspace t; mode main'
        v = 'workspace v; mode main'
        w = 'workspace w; mode main'
        x = 'workspace x; mode main'

        shift-a = 'move-to-workspace a; mode main'
        shift-c = 'move-to-workspace c; mode main'
        shift-d = 'move-to-workspace d; mode main'
        shift-f = 'move-to-workspace f; mode main'
        shift-o = 'move-to-workspace o; mode main'
        shift-p = 'move-to-workspace p; mode main'
        shift-r = 'move-to-workspace r; mode main'
        shift-s = 'move-to-workspace s; mode main'
        shift-t = 'move-to-workspace t; mode main'
        shift-v = 'move-to-workspace v; mode main'
        shift-w = 'move-to-workspace w; mode main'
        shift-x = 'move-to-workspace x; mode main'

        ctrl-a = 'move-to-workspace --follow a; mode main'
        ctrl-c = 'move-to-workspace --follow c; mode main'
        ctrl-d = 'move-to-workspace --follow d; mode main'
        ctrl-f = 'move-to-workspace --follow f; mode main'
        ctrl-o = 'move-to-workspace --follow o; mode main'
        ctrl-p = 'move-to-workspace --follow p; mode main'
        ctrl-r = 'move-to-workspace --follow r; mode main'
        ctrl-s = 'move-to-workspace --follow s; mode main'
        ctrl-t = 'move-to-workspace --follow t; mode main'
        ctrl-v = 'move-to-workspace --follow v; mode main'
        ctrl-w = 'move-to-workspace --follow w; mode main'
        ctrl-x = 'move-to-workspace --follow x; mode main'

        shift-semicolon = 'reload-config; mode main'

        # Link the focused window by hand.
        [mode.project.binding]
        esc = 'mode main'
        1 = 'link p; mode main'
        2 = 'link bil; mode main'
        3 = 'link iam; mode main'
        4 = 'link gc; mode main'
        0 = 'unlink; mode main'
        l = 'link --active; mode main'
        """#
}

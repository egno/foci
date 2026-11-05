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
        # 'text'     WORK · [w] x
        menu-bar-style = 'squares'

        gap = 0

        # Maximized windows are an accordion: the focused one leaves this many points at its left and right, where the
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
        # Windows 'focus-back' can go back to, most recently focused first.
        focus-history = 10

        # The leader: any of these keys. In bindings, 'leader' stands for all of them.
        # Tapped alone (right-cmd, left-alt, ...): still a modifier when held with another key.
        # 'hold-<key>' (hold-space): a plain key held down for 'hold-delay' milliseconds; tapped, or with another key
        # pressed before the delay (typing fast), it types as usual.
        leader = ['right-cmd', 'f20', 'ctrl-esc']
        hold-delay = 250

        # URL router: make Foci the default browser (System Settings > Desktop & Dock > Default web browser) and
        # links open in the browser of the project they were clicked in: the project's first app with 'open-url'.
        # A link from an unlinked window (Slack) goes to the active project. 'browser' opens links when that
        # project has no browser, or there is no active project, using its 'global-open-url'.
        # browser = 'chrome'

        # Displays are called 'built-in' (the laptop's screen) and 'ext 1'...'ext N' (the others, from the left);
        # 'main' is the one with the menu bar, and part of the model name ('dell') works too.
        # Display numbers (menu bar, 'focus-display 2', 'next|prev', workspaces below): these displays first, in
        # this order, then the rest left to right. Empty: all left to right.
        # display-order = ['built-in', 'ext 2', 'ext 1']

        # Workspace -> display: 'main' (menu bar), 'secondary' (the first other one in display order), a display
        # number (see 'display-order'), 'built-in', 'ext 2', or part of the model name. With three displays give the
        # third one its workspaces by number.
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
        #                project's 'open' items, quoted ({ app = 'vscode', open = ['~/src/work'] })
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

        # Examples, commented out: uncomment and adapt them (remove '# ' before the TOML lines). With
        # 'browser = ...' at the top and the projects' 'apps' lines below too, the examples are a working setup.

        """# + "\n" + commented(examples) + "\n\n" + #"""
        # ---------------------------------------------------------------- Projects
        # Order = 'project next|prev' order.
        # apps: the project's apps (see the examples above); their windows link to the project by the app's rules.
        # Without apps, link windows by hand: leader, space, '.' and the project's key.
        # autostart (default true): when you switch to the app's workspace in this project and the project has
        # no window of the app, launch it.
        # key (default: the first letter of the name): what '{project}' in a binding key stands for.
        [[projects]]
        name = 'Pet'
        # apps = ['firefox', { app = 'vscode', autostart = false, open = ['~/src/pet'] }, { app = 'kitty', autostart = false }]

        [[projects]]
        name = 'Work'
        # apps = ['chrome', { app = 'vscode', open = ['~/src/work'] }, 'kitty']

        # ---------------------------------------------------------------- Bindings
        # Commands (separate with ';'):
        #   project <name>|--none|next|prev    project-back-and-forth
        #   workspace <ws>    workspace-back-and-forth (= workspace back)
        #   move-to-workspace [--follow] <ws>
        #     <ws>: <name>, next|prev (the workspaces of the focused display), back (the previous workspace)
        #   move-to-display [--follow] <display>   the focused window to the workspace shown on that display
        #   move-workspace-to-display <display>    focus-display <display>
        #     <display>: next|prev (left to right, wrapping), left|right|up|down (the nearest one on that side),
        #     1-9 (display order, as in the menu bar), main, secondary, built-in, ext 1..N, part of the model name
        #   focus next|prev                    cycle windows of the focused workspace
        #   focus-app next|prev                cycle the focused app's windows (active project, unlinked), any workspace
        #   focus-back                         the previously focused window, in any project and workspace; with
        #                                      'repeat = true', each press goes further back in the last 'focus-history'
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
        enter = { run = 'focus-app next', label = 'next window of the app', repeat = true }
        tab = 'focus-display next'
        # Digits are displays, numbered from the left as in the menu bar.
        1 = { run = 'focus-display 1', label = 'display 1' }
        2 = { run = 'focus-display 2', label = 'display 2' }
        3 = { run = 'focus-display 3', label = 'display 3' }

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
        # slash = 'mode launch'   # see the [mode.launch] example above
        quote = 'mode layout'
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
        1 = { run = 'move-to-display 1', label = 'to display 1' }
        2 = { run = 'move-to-display 2', label = 'to display 2' }
        3 = { run = 'move-to-display 3', label = 'to display 3' }

        [mode.go]
        label = 'Go with window'

        [mode.go.binding]
        '{workspace}' = 'move-to-workspace --follow {workspace}'
        tab = { run = 'move-to-display --follow next', label = 'to next display' }
        1 = { run = 'move-to-display --follow 1', label = 'to display 1' }
        2 = { run = 'move-to-display --follow 2', label = 'to display 2' }
        3 = { run = 'move-to-display --follow 3', label = 'to display 3' }

        [mode.layout]
        label = 'Layout'

        [mode.layout.binding]
        enter = 'layout toggle'
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

        [mode.config]
        label = 'Config'

        [mode.config.binding]
        r = 'reload-config'
        e = { run = 'exec open -t ~/.config/foci/config.toml', label = 'edit config' }
        """#

    /// Example apps and the launch mode: in `text` as comments, valid TOML on their own (tested).
    static let examples = #"""
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

        # One kitty process per project.
        [apps.kitty]
        bundle-id = 'net.kovidgoyal.kitty'
        args = '--instance-group[= ]{project}( |$)'
        workspace = 'x'
        launch = '/Applications/kitty.app/Contents/MacOS/kitty --single-instance --instance-group {project} --directory "$HOME"'
        global-launch = 'open -na kitty'

        # One VS Code instance per project, opened on the project's 'open' items.
        [apps.vscode]
        bundle-id = 'com.microsoft.VSCode'
        args = '--user-data-dir[= ].*/\.vscode-projects/{project}( |$)'
        workspace = 'c'
        launch = 'code --user-data-dir "$HOME/.vscode-projects/{project}" {open}'
        global-launch = 'open -na "Visual Studio Code"'

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

        [apps.settings]
        bundle-id = 'com.apple.systempreferences'
        workspace = 'a'
        floating = true

        # Launch, or focus, the active project's window of an app: the key is the app's workspace. Uncomment the
        # 'slash' binding in [mode.control.binding] to open it.
        [mode.launch]
        label = 'Launch'

        [mode.launch.binding]
        w = 'launch chrome'
        c = 'launch vscode'
        x = 'launch kitty'
        f = 'launch firefox'
        """#

    /// TOML lines commented out with '# '; comment lines and blank lines stay as they are.
    static func commented(_ toml: String) -> String {
        toml.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty || $0.hasPrefix("#") ? String($0) : "# " + $0 }
            .joined(separator: "\n")
    }
}

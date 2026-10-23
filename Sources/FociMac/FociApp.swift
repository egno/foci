import AppKit
import FociCore
import os

/// Wires the engine to macOS: permissions, hotkeys, AX events, config reload, menu bar, clean quit.
@MainActor
public final class FociApp: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "dev.foci", category: "app")
    private let configSource = TOMLConfigSource()
    private let windowSystem = AXWindowSystem()
    private let hotkeys = Hotkeys()
    private let menu = StatusMenu()
    private let keyHints = KeyHintPanel()
    private var engine: Engine?
    private var refreshScheduled = false
    private var timer: Timer?
    private var configDate: Date?
    private var configProblems: [String] = []
    private var hotkeyProblems: [String] = []
    private var signalSources: [DispatchSourceSignal] = []
    /// Links that arrived before the engine started (e.g. Foci was launched to open one).
    private var pendingURLs: [(url: String, opener: [Int32])] = []
    private lazy var cliServer = CLIServer { [weak self] in self?.engine.map { CLIHandler(engine: $0) } }

    override public init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        installSignalHandlers()
        menu.onEditConfig = { [configSource] in NSWorkspace.shared.open(configSource.url) }
        guard AXWindowSystem.isTrusted(prompt: true) else {
            menu.setTitle("Foci ⚠ Accessibility")
            // Start as soon as the user grants the permission in System Settings.
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                MainActor.assumeIsolated {
                    guard AXWindowSystem.isTrusted(prompt: false) else { return }
                    self.timer?.invalidate()
                    self.start()
                }
            }
            return
        }
        start()
    }

    /// Links and HTML files, as the default browser. Called from inside the Apple Event, which names the sender.
    public func application(_ application: NSApplication, open urls: [URL]) {
        let sender = NSAppleEventManager.shared().currentAppleEvent?
            .attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value
        let opener = sender.map(ProcessArgs.ancestry) ?? []
        for url in urls {
            log.info("open \(url.absoluteString, privacy: .public) from \(opener, privacy: .public)")
            if let engine {
                for e in engine.openURL(url.absoluteString, opener: opener) { log.error("\(e, privacy: .public)") }
                updateMenu()
            } else {
                pendingURLs.append((url.absoluteString, opener))
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // Never leave windows parked off-screen.
        engine?.restoreAll()
        cliServer.stop()
    }

    private func start() {
        configSource.installDefaultIfMissing()
        let config = loadConfig() ?? Config()
        let engine = Engine(
            config: config, windowSystem: windowSystem, launcher: ShellLauncher(), store: JSONStateStore(),
            configSource: configSource)
        self.engine = engine
        menu.engine = engine

        engine.onBindingsChange = { [weak self] in
            self?.bindHotkeys()
            self?.updateKeyHints()
        }
        engine.onChange = { [weak self] in
            self?.updateMenu()
            self?.cliServer.publish(CLIHandler(engine: engine).status())
        }
        engine.onLog = { [log] in log.info("\($0, privacy: .public)") }
        hotkeys.onHotkey = { [weak self] script in
            self?.run(script, pressed: true)
            // A key that stays in the mode (resize) restarts the wait; a mode change already updated the hints.
            if self?.keyHints.isVisible == false { self?.updateKeyHints() }
        }
        menu.onCommand = { [weak self] script, window in self?.run(script, window: window) }
        windowSystem.onEvent = { [weak self] in self?.scheduleRefresh() }

        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
        ] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.displaysChanged() }
        }

        // Safety net for missed AX notifications, and config auto-reload.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.configSource.modificationDate != self.configDate { self.run("reload-config") }
                self.engine?.refresh()
            }
        }

        bindHotkeys()
        cliServer.start()
        engine.refresh()
        for (url, opener) in pendingURLs {
            for e in engine.openURL(url, opener: opener) { log.error("\(e, privacy: .public)") }
        }
        pendingURLs = []
        log.info("started")
    }

    private func loadConfig() -> Config? {
        configDate = configSource.modificationDate
        do {
            let c = try configSource.load()
            configProblems = c.validate() + [LoginItem.apply(c.startAtLogin)].compactMap { $0 }
            return c
        } catch {
            configProblems = ["config: \(error)"]
            return nil
        }
    }

    /// `pressed`: a key of the current mode, see `Engine.press`.
    private func run(_ script: String, window: WindowID? = nil, pressed: Bool = false) {
        guard let engine else { return }
        log.info("run: \(script, privacy: .public)\(window.map { " on \($0)" } ?? "", privacy: .public)")
        if script.contains("reload-config") { configDate = configSource.modificationDate }
        let errors = pressed ? engine.press(script) : engine.run(script, window: window)
        for e in errors { log.error("\(script, privacy: .public): \(e, privacy: .public)") }
        if script.contains("reload-config") {
            configProblems = errors + [LoginItem.apply(engine.config.startAtLogin)].compactMap { $0 }
        }
        updateMenu()
    }

    private func bindHotkeys() {
        guard let engine else { return }
        hotkeyProblems = hotkeys.register(engine.bindings)
        for e in hotkeyProblems { log.error("\(e, privacy: .public)") }
        updateMenu()
    }

    /// which-key: in any mode but `main`, list the mode's keys once no key was pressed for `key-hints-delay`.
    /// Moving to another mode while the hints are up shows its keys at once.
    private func updateKeyHints() {
        guard let engine, engine.config.keyHints, engine.mode != "main" else { return keyHints.hide() }
        let display = engine.display(of: engine.focusedWorkspace).id.raw
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display
        }
        keyHints.show(
            title: engine.modeTitle, hints: engine.keyHints, on: screen,
            after: keyHints.isVisible ? 0 : engine.config.keyHintsDelay)
    }

    private func updateMenu() {
        menu.setProblems(configProblems + hotkeyProblems)
        menu.update()
    }

    /// A display was connected or disconnected (or rearranged). macOS moves windows between displays for a
    /// while after the change; lay out again once it is done, so Foci has the last word.
    private func displaysChanged() {
        scheduleRefresh()
        for delay in [1.0, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.scheduleRefresh() }
        }
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        // Coalesce bursts of AX notifications (a new window fires several).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.engine?.refresh()
        }
    }

    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApplication.shared.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }
}

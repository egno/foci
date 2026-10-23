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
    private var engine: Engine?
    private var refreshScheduled = false
    private var timer: Timer?
    private var configDate: Date?
    private var configProblems: [String] = []
    private var hotkeyProblems: [String] = []
    private var signalSources: [DispatchSourceSignal] = []

    override public init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        installSignalHandlers()
        menu.onEditConfig = { [configSource] in NSWorkspace.shared.open(configSource.url) }
        guard AXWindowSystem.isTrusted(prompt: true) else {
            menu.show(title: "Foci ⚠ Accessibility", menu: nil)
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

    public func applicationWillTerminate(_ notification: Notification) {
        // Never leave windows parked off-screen.
        engine?.restoreAll()
    }

    private func start() {
        configSource.installDefaultIfMissing()
        let config = loadConfig() ?? Config()
        let engine = Engine(
            config: config, windowSystem: windowSystem, launcher: ShellLauncher(), store: JSONStateStore(),
            configSource: configSource)
        self.engine = engine

        engine.onBindingsChange = { [weak self] in self?.bindHotkeys() }
        engine.onChange = { [weak self] in self?.updateMenu() }
        engine.onLog = { [log] in log.info("\($0, privacy: .public)") }
        hotkeys.onHotkey = { [weak self] script in self?.run(script) }
        menu.onCommand = { [weak self] script in self?.run(script) }
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
            MainActor.assumeIsolated { self?.scheduleRefresh() }
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
        engine.refresh()
        log.info("started")
    }

    private func loadConfig() -> Config? {
        configDate = configSource.modificationDate
        do {
            let c = try configSource.load()
            configProblems = c.validate()
            return c
        } catch {
            configProblems = ["config: \(error)"]
            return nil
        }
    }

    private func run(_ script: String) {
        guard let engine else { return }
        log.info("run: \(script, privacy: .public)")
        if script.contains("reload-config") { configDate = configSource.modificationDate }
        let errors = engine.run(script)
        for e in errors { log.error("\(script, privacy: .public): \(e, privacy: .public)") }
        if script.contains("reload-config") { configProblems = errors }
        updateMenu()
    }

    private func bindHotkeys() {
        guard let engine else { return }
        hotkeyProblems = hotkeys.register(engine.config.modes[engine.mode] ?? [:])
        for e in hotkeyProblems { log.error("\(e, privacy: .public)") }
        updateMenu()
    }

    private func updateMenu() {
        guard let engine else { return }
        menu.setProblems(configProblems + hotkeyProblems)
        menu.update(engine: engine)
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

import AppKit
import OSLog
import ScreenCapKit

let appLog = Logger(subsystem: "com.contractorkeith.screencap", category: "app")

/// Owns the long-lived pieces: settings, history, the capture coordinator, shortcuts and the menu.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let launch: LaunchArguments
    private let settings = AppSettings()
    private let onboarding = PermissionOnboardingController()
    private let updater = UpdaterController()
    private lazy var settingsWindow = SettingsWindowController(settings: settings, updater: updater)
    private lazy var history = Self.openHistory(retentionDays: settings.historyRetentionDays)
    private let desktopIcons = DesktopIconsController()
    private lazy var coordinator = CaptureCoordinator(
        settings: settings,
        // Desktop-icon covers are ours but must stay in captures.
        service: CaptureService(includedOwnWindows: { @MainActor [desktopIcons] in desktopIcons.coverWindowIDs }),
        history: history,
        showOnboarding: { [weak self] in self?.onboarding.show() }
    )
    private lazy var historyWindow = HistoryWindowController(store: history, settings: settings)
    private lazy var urlRouter = URLSchemeRouter(
        handler: AppAutomationHandler(coordinator: coordinator, settingsWindow: settingsWindow,
                                      desktopIcons: desktopIcons),
        displayFrames: { NSScreen.screens.map(\.frame) }
    )
    /// URLs that arrive before launch finishes are run once it has.
    private var pendingURLs: [URL]? = []
    private lazy var sinkRouter = CaptureSinkRouter(fallback: SavingCaptureSink(output: coordinator.output))
    private var shortcuts: ShortcutController?
    private var menuBar: MenuBarController?
    private var historyRetention: HistoryRetention?

    init(launch: LaunchArguments) {
        self.launch = launch
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon. LSUIElement does this for the bundle; this covers `swift run`.
        NSApp.setActivationPolicy(.accessory)
        coordinator.sink = sinkRouter
        onboarding.firstCapture = { [weak self] in _ = self?.coordinator.capture(.area) }
        installFeatures()
        menuBar = MenuBarController(entries: AppMenu.entries(menuActions))
        let shortcuts = ShortcutController { [weak self] command in self?.perform(command) }
        shortcuts.register()
        self.shortcuts = shortcuts
        pendingURLs.map { $0.forEach(urlRouter.open) }
        pendingURLs = nil
        appLog.notice("ScreenCap launched, status item visible: \(self.menuBar?.isVisible ?? false)")

        if launch.requestsCapture {
            coordinator.runLaunchCapture(launch)
        } else if onboarding.shouldShowAtLaunch {
            onboarding.show()
        }
    }

    /// `screencap://` commands and files opened from Finder / `open -a` (the router sends files to the editor).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            appLog.notice("Received URL: \(url.absoluteString, privacy: .public)")
        }
        if pendingURLs != nil {
            pendingURLs?.append(contentsOf: urls)
        } else {
            urls.forEach(urlRouter.open)
        }
    }

    /// Unsaved editor windows ask Save / Don't Save / Cancel first (#73).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let editor = sinkRouter.annotate as? EditorCoordinator else { return .terminateNow }
        return editor.reviewUnsavedBeforeQuit { sender.reply(toApplicationShouldTerminate: $0) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        desktopIcons.show()
    }

    private var menuActions: AppMenu.Actions {
        AppMenu.Actions(
            capture: { [weak self] kind in self?.coordinator.capture(kind) },
            selfTimer: { [weak self] seconds in self?.coordinator.startSelfTimer(seconds: seconds) },
            selfTimerSeconds: { [weak self] in self?.settings.selfTimerSeconds ?? 0 },
            openSettings: { [weak self] in self?.settingsWindow.show() },
            openHistory: { NotificationCenter.default.post(name: .openHistoryRequested, object: nil) },
            toggleDesktopIcons: { [weak self] in self?.desktopIcons.apply(.toggle) },
            desktopIconsHidden: { [weak self] in self?.desktopIcons.isHidden ?? false },
            openOnboarding: { [weak self] in self?.onboarding.show() },
            toggleLaunchAtLogin: { LaunchAtLogin.toggle() },
            launchAtLoginIsOn: { LaunchAtLogin.isEnabled },
            quit: { NSApp.terminate(nil) },
            pinFromClipboard: { [weak self] in self?.pins.pinFromClipboard() },
            unlockAllPins: { [weak self] in self?.pins.unlockAll() },
            checkForUpdates: { [weak self] in self?.updater.checkForUpdates() }
        )
    }

    private func perform(_ command: ShortcutCatalog.Command) {
        switch command {
        case let .capture(kind):
            coordinator.capture(kind)
        case .openHistory:
            NotificationCenter.default.post(name: .openHistoryRequested, object: nil)
        case .toggleOverlays:
            NotificationCenter.default.post(name: .toggleOverlaysRequested, object: nil)
        }
    }

    // MARK: - Feature hooks

    /// Each UI feature creates its controller here and assigns itself on `sinkRouter`
    /// (overlay, annotate, pin). Keep one line per feature so parallel PRs merge cleanly.
    private func installFeatures() {
        sinkRouter.annotate = EditorCoordinator.install(settings: settings)
        settingsWindow.history = history // Screenshots, Wallpaper, Advanced, About panes (#28)
        _ = historyWindow // History window, opens on .openHistoryRequested (#28)
        historyRetention = history.map { HistoryRetention(store: $0, settings: settings) } // Live purge (#86)
        historyRetention?.start()
        coordinator.desktopIcons = desktopIcons // Hide desktop icons while capturing (#28)
        ScrollingCaptureController.install(on: coordinator)
        sinkRouter.pin = pins
        textCapture.install()
        coordinator.textHandler = { [textCapture] image in try await textCapture.recognize(image) }
        sinkRouter.overlay = QuickAccessController(settings: settings, output: coordinator.output,
                                                   history: coordinator.history, router: sinkRouter)
    }

    private lazy var pins: PinController = {
        let pins = PinController(output: coordinator.output)
        pins.install()
        return pins
    }()
    private lazy var textCapture = TextCaptureController(
        settings: settings, service: coordinator.service, history: coordinator.history
    )

    private static func openHistory(retentionDays: Int) -> HistoryStore? {
        do {
            return try HistoryStore(retentionDays: retentionDays)
        } catch {
            appLog.error("History unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

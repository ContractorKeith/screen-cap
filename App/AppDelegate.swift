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
    private lazy var settingsWindow = SettingsWindowController(settings: settings)
    private lazy var coordinator = CaptureCoordinator(
        settings: settings,
        history: Self.openHistory(),
        showOnboarding: { [weak self] in self?.onboarding.show() }
    )
    private var shortcuts: ShortcutController?
    private var menuBar: MenuBarController?

    init(launch: LaunchArguments) {
        self.launch = launch
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon. LSUIElement does this for the bundle; this covers `swift run`.
        NSApp.setActivationPolicy(.accessory)
        menuBar = MenuBarController(entries: AppMenu.entries(menuActions))
        let shortcuts = ShortcutController { [weak self] command in self?.perform(command) }
        shortcuts.register()
        self.shortcuts = shortcuts
        appLog.notice("ScreenCap launched, status item visible: \(self.menuBar?.isVisible ?? false)")

        if let kind = launch.capture {
            runLaunchCapture(kind)
        } else if !ScreenRecordingPermission.isGranted {
            onboarding.show()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // URL scheme routing arrives in M7; log for now.
        for url in urls {
            appLog.info("Received URL: \(url.absoluteString, privacy: .public)")
        }
    }

    private var menuActions: AppMenu.Actions {
        AppMenu.Actions(
            capture: { [weak self] kind in self?.coordinator.capture(kind) },
            selfTimer: { [weak self] seconds in self?.coordinator.startSelfTimer(seconds: seconds) },
            selfTimerSeconds: { [weak self] in self?.settings.selfTimerSeconds ?? 0 },
            openSettings: { [weak self] in self?.settingsWindow.show() },
            openOnboarding: { [weak self] in self?.onboarding.show() },
            toggleLaunchAtLogin: { LaunchAtLogin.toggle() },
            launchAtLoginIsOn: { LaunchAtLogin.isEnabled },
            quit: { NSApp.terminate(nil) }
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

    /// `--capture <kind>`: same path as the shortcut; `--quit` exits when it is delivered.
    private func runLaunchCapture(_ kind: CaptureKind) {
        appLog.notice("Launch capture: \(kind.rawValue, privacy: .public)")
        let task = if kind == .window, let app = launch.windowApp {
            coordinator.captureWindow(ofApp: app, action: launch.action)
        } else {
            coordinator.capture(kind, action: launch.action)
        }
        guard launch.quitAfterCapture else { return }
        Task {
            await task?.value
            NSApp.terminate(nil)
        }
    }

    private static func openHistory() -> HistoryStore? {
        do {
            return try HistoryStore()
        } catch {
            appLog.error("History unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

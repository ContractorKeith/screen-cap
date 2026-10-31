import AppKit
import OSLog

let appLog = Logger(subsystem: "com.contractorkeith.screencap", category: "app")

/// Owns the menu bar item and the app's windows.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private let settingsWindow = SettingsWindowController()
    private let onboarding = PermissionOnboardingController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon. LSUIElement does this for the bundle; this covers `swift run`.
        NSApp.setActivationPolicy(.accessory)
        menuBar = MenuBarController(
            openSettings: { [weak self] in self?.settingsWindow.show() },
            openOnboarding: { [weak self] in self?.onboarding.show() }
        )
        if !ScreenRecordingPermission.isGranted {
            onboarding.show()
        }
        appLog.notice("ScreenCap launched, status item visible: \(self.menuBar?.isVisible ?? false)")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // URL scheme routing arrives in M7; log for now.
        for url in urls {
            appLog.info("Received URL: \(url.absoluteString, privacy: .public)")
        }
    }
}

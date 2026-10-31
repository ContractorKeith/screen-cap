import AppKit
import ServiceManagement

/// Status item and its menu. Capture items are placeholders until M1.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let launchAtLoginItem = NSMenuItem(
        title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: ""
    )
    private let openSettings: () -> Void
    private let openOnboarding: () -> Void

    var isVisible: Bool { statusItem.isVisible && statusItem.button != nil }

    init(openSettings: @escaping () -> Void, openOnboarding: @escaping () -> Void) {
        self.openSettings = openSettings
        self.openOnboarding = openOnboarding
        super.init()
        statusItem.button?.image = NSImage(
            systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenCap"
        )
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(item("Capture Area", #selector(captureArea)))
        menu.addItem(item("Capture Window", #selector(captureWindow)))
        menu.addItem(item("Capture Fullscreen", #selector(captureFullscreen)))
        menu.addItem(.separator())
        menu.addItem(item("Screen Recording Permission…", #selector(showOnboarding)))
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit ScreenCap", #selector(quit), key: "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    // Refresh the checkmark each time the menu opens; the user can change it in System Settings.
    func menuWillOpen(_ menu: NSMenu) {
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func captureArea() { appLog.info("Capture Area (placeholder)") }
    @objc private func captureWindow() { appLog.info("Capture Window (placeholder)") }
    @objc private func captureFullscreen() { appLog.info("Capture Fullscreen (placeholder)") }
    @objc private func showSettings() { openSettings() }
    @objc private func showOnboarding() { openOnboarding() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            // Fails when run outside a .app bundle (e.g. `swift run`).
            appLog.error("Launch at Login toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

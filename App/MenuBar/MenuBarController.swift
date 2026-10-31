import AppKit
@preconcurrency import KeyboardShortcuts
import ServiceManagement

/// Status item whose menu is built from `MenuEntry` data.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    var isVisible: Bool { statusItem.isVisible && statusItem.button != nil }

    init(entries: [MenuEntry]) {
        super.init()
        statusItem.button?.image = NSImage(
            systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenCap"
        )
        setEntries(entries)
    }

    /// Replaces the whole menu, e.g. after a feature registers new rows.
    func setEntries(_ entries: [MenuEntry]) {
        let menu = MenuBuilder.menu(from: entries)
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        MenuBuilder.refreshStates(in: menu)
        // Global shortcuts need a different Carbon handler while a menu is tracking.
        KeyboardShortcuts.isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        KeyboardShortcuts.isMenuOpen = false
    }
}

/// Launch at Login via `SMAppService`; only works from a .app bundle.
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func toggle() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            appLog.error("Launch at Login toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

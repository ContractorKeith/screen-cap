import Foundation
import ScreenCapKit

/// The status menu's contents. Add a row here to add a menu item.
@MainActor
enum AppMenu {
    /// Everything the menu can trigger, injected so tests can record calls.
    struct Actions {
        var capture: @MainActor (CaptureKind) -> Void
        var selfTimer: @MainActor (Int) -> Void
        var selfTimerSeconds: @MainActor () -> Int
        var openSettings: @MainActor () -> Void
        var openHistory: @MainActor () -> Void
        var toggleDesktopIcons: @MainActor () -> Void
        var desktopIconsHidden: @MainActor () -> Bool
        var openOnboarding: @MainActor () -> Void
        var toggleLaunchAtLogin: @MainActor () -> Void
        var launchAtLoginIsOn: @MainActor () -> Bool
        var quit: @MainActor () -> Void
        var pinFromClipboard: @MainActor () -> Void = {}
        var unlockAllPins: @MainActor () -> Void = {}
    }

    static func entries(_ actions: Actions) -> [MenuEntry] {
        [
            capture("Capture Area", .area, actions),
            capture("Capture Window", .window, actions),
            capture("Capture Fullscreen", .fullscreen, actions),
            capture("All-In-One", .allInOne, actions),
            .submenu("Capture", [
                capture("Capture Previous Area", .previousArea, actions),
                .submenu("Self-Timer", selfTimerEntries(actions)),
                capture("Scrolling Capture", .scrolling, actions),
                capture("Capture Text", .text, actions),
                .separator,
                .item(MenuAction("Pin from Clipboard", perform: actions.pinFromClipboard)),
                .item(MenuAction("Unlock All Pins", perform: actions.unlockAllPins))
            ]),
            .submenu("Annotate", EditorMenu.entries),
            .item(MenuAction("Hide Overlays", shortcut: .toggleOverlays, isOn: { QuickAccessVisibility.isHidden },
                             perform: post(.toggleOverlaysRequested))),
            .item(MenuAction("Restore Recently Closed", perform: post(.restoreRecentlyClosedRequested))),
            .separator,
            .item(MenuAction("History…", shortcut: .openHistory, perform: actions.openHistory)),
            .item(MenuAction("Hide Desktop Icons", isOn: actions.desktopIconsHidden,
                             perform: actions.toggleDesktopIcons)),
            .separator,
            .item(MenuAction("Screen Recording Permission…", perform: actions.openOnboarding)),
            .item(MenuAction("Launch at Login", isOn: actions.launchAtLoginIsOn, perform: actions.toggleLaunchAtLogin)),
            .item(MenuAction("Settings…", keyEquivalent: ",", perform: actions.openSettings)),
            .separator,
            .item(MenuAction("Quit ScreenCap", keyEquivalent: "q", perform: actions.quit))
        ]
    }

    /// A row that asks a feature to act by posting its notification (Quick Access observes these).
    private static func post(_ name: Notification.Name) -> @MainActor () -> Void {
        { NotificationCenter.default.post(name: name, object: nil) }
    }

    private static func capture(_ title: String, _ kind: CaptureKind, _ actions: Actions) -> MenuEntry {
        .item(MenuAction(title, shortcut: ShortcutCatalog.name(for: kind)) { actions.capture(kind) })
    }

    /// "Start (5 s)" with the shortcut, then one row per length; the current length is checked.
    private static func selfTimerEntries(_ actions: Actions) -> [MenuEntry] {
        let start = MenuEntry.item(MenuAction("Start", shortcut: .selfTimer) { actions.capture(.selfTimer) })
        let lengths = AppSettings.Defaults.selfTimerChoices.map { seconds in
            MenuEntry.item(MenuAction(
                "\(seconds) seconds",
                isOn: { actions.selfTimerSeconds() == seconds },
                perform: { actions.selfTimer(seconds) }
            ))
        }
        return [start, .separator] + lengths
    }
}

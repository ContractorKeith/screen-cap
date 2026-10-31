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
        var openOnboarding: @MainActor () -> Void
        var toggleLaunchAtLogin: @MainActor () -> Void
        var launchAtLoginIsOn: @MainActor () -> Bool
        var quit: @MainActor () -> Void
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
                capture("Capture Text", .text, actions)
            ]),
            .submenu("Annotate", EditorMenu.entries),
            .separator,
            .item(MenuAction("Screen Recording Permission…", perform: actions.openOnboarding)),
            .item(MenuAction("Launch at Login", isOn: actions.launchAtLoginIsOn, perform: actions.toggleLaunchAtLogin)),
            .item(MenuAction("Settings…", keyEquivalent: ",", perform: actions.openSettings)),
            .separator,
            .item(MenuAction("Quit ScreenCap", keyEquivalent: "q", perform: actions.quit))
        ]
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

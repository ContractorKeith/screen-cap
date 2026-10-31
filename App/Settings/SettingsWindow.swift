import AppKit
import ScreenCapKit
import SwiftUI

/// Which tab is showing. Remembered across launches ("last-used tab" for `open-settings`).
@MainActor
@Observable
final class SettingsNavigation {
    static let defaultsKey = "settingsTab"
    var tab: String { didSet { UserDefaults.standard.set(tab, forKey: Self.defaultsKey) } }

    init() {
        tab = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? AutomationCommand.SettingsTab.general.rawValue
    }
}

/// Settings tabs (PLAN §3.4). Later features add a tab here with `.tabItem` and a `.tag`:
/// use the `AutomationCommand.SettingsTab` raw value when one exists, so
/// `screencap://open-settings?tab=` can select it; otherwise any unique string.
struct SettingsView: View {
    let settings: AppSettings
    let history: HistoryStore?
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        TabView(selection: $navigation.tab) {
            GeneralSettingsPane(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(AutomationCommand.SettingsTab.general.rawValue)
            ShortcutsSettingsPane()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(AutomationCommand.SettingsTab.shortcuts.rawValue)
            QuickAccessSettingsPane(settings: settings)
                .tabItem { Label("Quick Access", systemImage: "rectangle.stack") }
                .tag(AutomationCommand.SettingsTab.quickAccess.rawValue)
            ScreenshotsSettingsPane(settings: settings)
                .tabItem { Label("Screenshots", systemImage: "camera.viewfinder") }
                .tag(AutomationCommand.SettingsTab.screenshots.rawValue)
            ScrollingSettingsPane(settings: .shared)
                .tabItem { Label("Scrolling", systemImage: "scroll") }
                .tag("scrolling")
            TextRecognitionSettingsPane(settings: settings)
                .tabItem { Label("Text Recognition", systemImage: "text.viewfinder") }
                .tag("text")
            AnnotateSettingsPane(settings: settings)
                .tabItem { Label("Annotate", systemImage: "pencil.and.outline") }
                .tag(AutomationCommand.SettingsTab.annotate.rawValue)
            WallpaperSettingsPane(settings: settings)
                .tabItem { Label("Wallpaper", systemImage: "photo.on.rectangle") }
                .tag(AutomationCommand.SettingsTab.wallpaper.rawValue)
            AdvancedSettingsPane(settings: settings, history: history)
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
                .tag(AutomationCommand.SettingsTab.advanced.rawValue)
            AboutSettingsPane()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(AutomationCommand.SettingsTab.about.rawValue)
        }
        .frame(width: 680, height: 580)
    }
}

@MainActor
final class SettingsWindowController {
    private let settings: AppSettings
    /// Set in `AppDelegate.installFeatures()` before the window is first shown.
    var history: HistoryStore?
    let navigation = SettingsNavigation()
    private var window: NSWindow?

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// Shows Settings, switching to `tab` when given (otherwise the last-used tab).
    func show(tab: AutomationCommand.SettingsTab? = nil) {
        if let tab { navigation.tab = tab.rawValue }
        if window == nil {
            let view = SettingsView(settings: settings, history: history, navigation: navigation)
            let newWindow = NSWindow(contentViewController: NSHostingController(rootView: view))
            newWindow.title = "ScreenCap Settings"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

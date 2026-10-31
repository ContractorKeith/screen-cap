import AppKit
import ScreenCapKit
import SwiftUI

/// Which tab is showing. Remembered across launches ("last-used tab" for `open-settings`).
/// Typed, so only a real tab can be selected or persisted; an unknown stored value opens General.
@MainActor
@Observable
final class SettingsNavigation {
    static let defaultsKey = SettingsKeys.settingsTab
    @ObservationIgnored private let defaults: UserDefaults
    var tab: AutomationCommand.SettingsTab {
        didSet { defaults.set(tab.rawValue, forKey: Self.defaultsKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tab = defaults.string(forKey: Self.defaultsKey).flatMap(AutomationCommand.SettingsTab.init) ?? .general
    }
}

/// Settings tabs (PLAN §3.4). A new tab needs an `AutomationCommand.SettingsTab` case (its URL
/// spelling for `screencap://open-settings?tab=`) and a `.tabItem` plus `.tag` here.
struct SettingsView: View {
    let settings: AppSettings
    let history: HistoryStore?
    let updater: UpdaterController
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        TabView(selection: $navigation.tab) {
            GeneralSettingsPane(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(AutomationCommand.SettingsTab.general)
            ShortcutsSettingsPane()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(AutomationCommand.SettingsTab.shortcuts)
            QuickAccessSettingsPane(settings: settings)
                .tabItem { Label("Quick Access", systemImage: "rectangle.stack") }
                .tag(AutomationCommand.SettingsTab.quickAccess)
            ScreenshotsSettingsPane(settings: settings)
                .tabItem { Label("Screenshots", systemImage: "camera.viewfinder") }
                .tag(AutomationCommand.SettingsTab.screenshots)
            ScrollingSettingsPane(settings: .shared)
                .tabItem { Label("Scrolling", systemImage: "scroll") }
                .tag(AutomationCommand.SettingsTab.scrolling)
            TextRecognitionSettingsPane(settings: settings)
                .tabItem { Label("Text Recognition", systemImage: "text.viewfinder") }
                .tag(AutomationCommand.SettingsTab.text)
            AnnotateSettingsPane(settings: settings)
                .tabItem { Label("Annotate", systemImage: "pencil.and.outline") }
                .tag(AutomationCommand.SettingsTab.annotate)
            WallpaperSettingsPane(settings: settings)
                .tabItem { Label("Wallpaper", systemImage: "photo.on.rectangle") }
                .tag(AutomationCommand.SettingsTab.wallpaper)
            AdvancedSettingsPane(settings: settings, history: history, updater: updater)
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
                .tag(AutomationCommand.SettingsTab.advanced)
            AboutSettingsPane()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(AutomationCommand.SettingsTab.about)
        }
        .frame(width: 680, height: 580)
    }
}

@MainActor
final class SettingsWindowController {
    private let settings: AppSettings
    private let updater: UpdaterController
    /// Set in `AppDelegate.installFeatures()` before the window is first shown.
    var history: HistoryStore?
    let navigation = SettingsNavigation()
    private var window: NSWindow?

    init(settings: AppSettings, updater: UpdaterController) {
        self.settings = settings
        self.updater = updater
    }

    /// Shows Settings, switching to `tab` when given (otherwise the last-used tab).
    func show(tab: AutomationCommand.SettingsTab? = nil) {
        if let tab { navigation.tab = tab }
        if window == nil {
            let view = SettingsView(settings: settings, history: history, updater: updater, navigation: navigation)
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

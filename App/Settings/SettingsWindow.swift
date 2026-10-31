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

/// Settings panes (PLAN §3.4) as a sidebar list beside the selected pane: ten tabs don't fit a
/// tab row without truncating their titles (#104). A new pane needs an `AutomationCommand.SettingsTab`
/// case (its URL spelling for `screencap://open-settings?tab=`), a `title`/`symbol` and a `pane` case.
struct SettingsView: View {
    let settings: AppSettings
    let history: HistoryStore?
    let updater: UpdaterController
    @Bindable var navigation: SettingsNavigation

    static let sidebarWidth: CGFloat = 180
    /// Panes are laid out for this size; the width is what the shortcut recorders and popups need.
    static let paneSize = CGSize(width: 660, height: 580)
    /// Shortest the window gets on a small screen; the panes scroll below their full height (#115).
    static let minPaneHeight: CGFloat = 360
    /// Sidebar, divider and pane at full height.
    static var contentSize: CGSize { CGSize(width: sidebarWidth + 1 + paneSize.width, height: paneSize.height) }

    var body: some View {
        HStack(spacing: 0) {
            List(AutomationCommand.SettingsTab.allCases, id: \.self, selection: selection) { tab in
                Label(tab.title, systemImage: tab.symbol)
            }
            .listStyle(.sidebar)
            .frame(width: Self.sidebarWidth)
            Divider()
            pane(navigation.tab)
                .frame(width: Self.paneSize.width)
                .frame(maxHeight: .infinity)
        }
        .frame(minHeight: Self.minPaneHeight, idealHeight: Self.paneSize.height, maxHeight: Self.paneSize.height)
    }

    /// List selection is optional; clicking empty sidebar space mustn't clear the tab.
    private var selection: Binding<AutomationCommand.SettingsTab?> {
        Binding(get: { navigation.tab }, set: { if let tab = $0 { navigation.tab = tab } })
    }

    @ViewBuilder
    private func pane(_ tab: AutomationCommand.SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettingsPane(settings: settings)
        case .shortcuts: ShortcutsSettingsPane()
        case .quickAccess: QuickAccessSettingsPane(settings: settings)
        case .screenshots: ScreenshotsSettingsPane(settings: settings)
        case .scrolling: ScrollingSettingsPane(settings: .shared)
        case .text: TextRecognitionSettingsPane(settings: settings)
        case .annotate: AnnotateSettingsPane(settings: settings)
        case .wallpaper: WallpaperSettingsPane(settings: settings)
        case .advanced: AdvancedSettingsPane(settings: settings, history: history, updater: updater)
        case .about: AboutSettingsPane()
        }
    }
}

extension AutomationCommand.SettingsTab {
    /// Sidebar title.
    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .quickAccess: "Quick Access"
        case .screenshots: "Screenshots"
        case .scrolling: "Scrolling"
        case .text: "Text Recognition"
        case .annotate: "Annotate"
        case .wallpaper: "Wallpaper"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    /// SF Symbol shown beside the title.
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "keyboard"
        case .quickAccess: "rectangle.stack"
        case .screenshots: "camera.viewfinder"
        case .scrolling: "scroll"
        case .text: "text.viewfinder"
        case .annotate: "pencil.and.outline"
        case .wallpaper: "photo.on.rectangle"
        case .advanced: "slider.horizontal.3"
        case .about: "info.circle"
        }
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

    static let autosaveName = "ScreenCapSettingsWindow"

    /// Shows Settings, switching to `tab` when given (otherwise the last-used tab). Opens at full
    /// size when it fits, shorter (panes scroll) when it doesn't, always inside the screen's
    /// visible frame at the remembered position (#115).
    func show(tab: AutomationCommand.SettingsTab? = nil) {
        if let tab { navigation.tab = tab }
        if let window {
            WindowPlacement.clampOnScreen(window)
        } else {
            let view = SettingsView(settings: settings, history: history, updater: updater, navigation: navigation)
            let hosting = NSHostingController(rootView: view)
            // The window, not SwiftUI, owns the size: fixed width, height between min and full.
            hosting.sizingOptions = []
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "ScreenCap Settings"
            newWindow.styleMask = [.titled, .closable, .resizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.contentMinSize = CGSize(width: SettingsView.contentSize.width, height: SettingsView.minPaneHeight)
            newWindow.contentMaxSize = SettingsView.contentSize
            WindowPlacement.placeNew(newWindow, autosaveName: Self.autosaveName, contentSize: SettingsView.contentSize)
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

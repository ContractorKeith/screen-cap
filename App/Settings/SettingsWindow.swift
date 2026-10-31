import AppKit
import ScreenCapKit
import SwiftUI

/// Settings tabs. Later features add a tab here (PLAN §3.4).
struct SettingsView: View {
    let settings: AppSettings

    var body: some View {
        TabView {
            GeneralSettingsPane(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsSettingsPane()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            TextRecognitionSettingsPane(settings: settings)
                .tabItem { Label("Text Recognition", systemImage: "text.viewfinder") }
        }
        .frame(width: 520, height: 560)
    }
}

@MainActor
final class SettingsWindowController {
    private let settings: AppSettings
    private var window: NSWindow?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show() {
        if window == nil {
            let view = SettingsView(settings: settings)
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

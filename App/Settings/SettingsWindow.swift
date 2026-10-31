import AppKit
import ScreenCapKit
import SwiftUI

/// Settings window stub. Tabs from PLAN §3.4 arrive in later milestones.
struct SettingsView: View {
    var body: some View {
        TabView {
            Form {
                LabeledContent("Version", value: ScreenCapKit.version)
                Text("More settings arrive in later milestones.")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 420, height: 220)
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let newWindow = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
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

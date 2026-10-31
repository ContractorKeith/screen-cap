import AppKit
import ScreenCapKit
import SwiftUI

/// History retention, reset and launch at login.
struct AdvancedSettingsPane: View {
    @Bindable var settings: AppSettings
    let history: HistoryStore?
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var confirmingReset = false
    @State private var status: String?

    static let retentionChoices = [1, 7, 14, 30, 60, 90]

    var body: some View {
        Form {
            Section("History") {
                Picker("Keep captures for", selection: $settings.historyRetentionDays) {
                    ForEach(Self.retentionChoices, id: \.self) { days in
                        Text(days == 1 ? "1 day" : "\(days) days").tag(days)
                    }
                }
                HStack {
                    Button("Purge Now", action: purge)
                        .disabled(history == nil)
                    Button("Open History Folder") {
                        NSWorkspace.shared.open(history?.directory ?? HistoryStore.defaultDirectory)
                    }
                    if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, wanted in
                        if wanted != LaunchAtLogin.isEnabled { LaunchAtLogin.toggle() }
                        launchAtLogin = LaunchAtLogin.isEnabled
                        settings.launchAtLogin = launchAtLogin
                    }
            }
            Section("Reset") {
                Button("Reset All Settings…", role: .destructive) { confirmingReset = true }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
        .confirmationDialog("Reset all settings to their defaults?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { settings.resetToDefaults() }
        } message: {
            Text("Shortcuts, saved captures and Launch at Login are not changed.")
        }
    }

    private func purge() {
        guard let history else { return }
        let days = settings.historyRetentionDays
        Task {
            let removed = (try? await history.purge(olderThan: days))?.count ?? 0
            status = removed == 1 ? "Removed 1 capture" : "Removed \(removed) captures"
        }
    }
}

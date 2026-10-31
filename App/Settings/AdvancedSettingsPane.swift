import AppKit
import ScreenCapKit
import SwiftUI

/// History retention, updates, reset and launch at login.
struct AdvancedSettingsPane: View {
    @Bindable var settings: AppSettings
    let history: HistoryStore?
    let updater: UpdaterController
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var autoUpdate = false
    @State private var confirmingReset = false
    @State private var status: String?
    /// A shorter retention waiting for confirmation (#101).
    @State private var pendingRetention: RetentionChange?

    static let retentionChoices = [1, 7, 14, 30, 60, 90]

    var body: some View {
        Form {
            Section("History") {
                Picker("Keep captures for", selection: retentionBinding) {
                    ForEach(Self.retentionChoices, id: \.self) { days in
                        Text(RetentionChange.days(days)).tag(days)
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
            Section("Updates") {
                Toggle("Automatically check for updates", isOn: $autoUpdate)
                    .disabled(!updater.isEnabled)
                    .onChange(of: autoUpdate) { _, wanted in updater.automaticallyChecksForUpdates = wanted }
                HStack {
                    Button("Check Now") { updater.checkForUpdates() }
                    if !updater.isEnabled {
                        Text("This build isn't set up for automatic updates; Check Now opens the releases page.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Reset") {
                Button("Reset All Settings…", role: .destructive) { confirmingReset = true }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
            autoUpdate = updater.automaticallyChecksForUpdates
        }
        .confirmationDialog("Reset all settings to their defaults?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { SettingsReset.resetAll(settings: settings) }
        } message: {
            Text("Shortcuts, saved captures, update checks and Launch at Login are not changed.")
        }
        .confirmationDialog(pendingRetention?.title ?? "", isPresented: confirmingRetention,
                            presenting: pendingRetention) { change in
            Button("Delete", role: .destructive) { finishRetention(change, confirmed: true) }
            Button("Cancel", role: .cancel) { finishRetention(change, confirmed: false) }
        } message: { change in
            Text(change.message)
        }
    }

    /// The picker writes through here so a shorter window that deletes captures asks first.
    private var retentionBinding: Binding<Int> {
        Binding(get: { settings.historyRetentionDays }, set: { requestRetention($0) })
    }

    private var confirmingRetention: Binding<Bool> {
        Binding(get: { pendingRetention != nil }, set: { if !$0 { pendingRetention = nil } })
    }

    private func requestRetention(_ days: Int) {
        let current = settings.historyRetentionDays
        guard days < current, let history else {
            settings.historyRetentionDays = days
            return
        }
        Task {
            let count = await history.count(olderThan: days)
            switch RetentionChange.decide(from: current, to: days, expiring: count) {
            case let .apply(value): settings.historyRetentionDays = value
            case let .confirm(change): pendingRetention = change
            }
        }
    }

    private func finishRetention(_ change: RetentionChange, confirmed: Bool) {
        settings.historyRetentionDays = change.resolve(confirmed: confirmed)
        pendingRetention = nil
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

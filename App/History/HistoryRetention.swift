import Foundation
import Observation
import ScreenCapKit

/// Keeps capture history inside the retention setting while the app runs (#86): purges on
/// start, hourly, and whenever Advanced → Keep captures for changes.
@MainActor
final class HistoryRetention {
    static let interval: TimeInterval = 60 * 60

    private let store: HistoryStore
    private let settings: AppSettings
    private var timer: Timer?
    /// Purges run in order so a quick run of setting changes ends on the last one.
    private var last: Task<Void, Never>?

    init(store: HistoryStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    func start() {
        applySetting()
        observeSetting()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.purge() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops the hourly purge (tests; the app keeps one for its lifetime).
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Waits for queued purges to finish (tests).
    func settled() async {
        await last?.value
    }

    /// Deletes everything past the current window.
    func purge() {
        enqueue { store in try await store.purgeExpired() }
    }

    private func applySetting() {
        let days = settings.historyRetentionDays
        enqueue { store in try await store.setRetention(days: days) }
    }

    private func observeSetting() {
        withObservationTracking {
            _ = settings.historyRetentionDays
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applySetting()
                self?.observeSetting()
            }
        }
    }

    private func enqueue(_ work: @escaping @Sendable (HistoryStore) async throws -> [UUID]) {
        let previous = last
        last = Task { [store] in
            await previous?.value
            do {
                let removed = try await work(store)
                guard !removed.isEmpty else { return }
                TempFiles.shared.release(records: removed) // temp copies of expired captures (#114)
                appLog.notice("History retention purged \(removed.count) capture(s)")
                NotificationCenter.default.post(name: .historyRecordsChanged, object: nil)
            } catch {
                appLog.error("History purge failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

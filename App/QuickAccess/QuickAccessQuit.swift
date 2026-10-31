import Foundation
import ScreenCapKit

/// What the quit path needs from history: HistoryStore in the app, a fake in tests.
protocol ClosedRecordStore: Sendable {
    func recordClosed(id: UUID) async throws
}

extension HistoryStore: ClosedRecordStore {
    func recordClosed(id: UUID) async throws {
        _ = try markClosed(id: id)
    }
}

/// Panels still open at quit count as closed, so Restore Recently Closed brings them back
/// after relaunch (#103).
enum QuickAccessQuit {
    /// Marks each record closed. `ids` are newest first; they're closed oldest first so the
    /// newest panel is the first one restored. Failures are skipped, not fatal to quitting.
    static func recordClosed(_ ids: [UUID], in store: any ClosedRecordStore) async {
        var seen = Set<UUID>()
        for id in ids.reversed() where seen.insert(id).inserted {
            do { try await store.recordClosed(id: id) } catch {
                appLog.error("Couldn't mark \(id.uuidString, privacy: .public) closed at quit")
            }
        }
    }

    /// `recordClosed`, blocking the caller (`applicationWillTerminate`, which can't await) for at
    /// most `timeout`. The store is an actor off the main thread, so waiting here can't deadlock.
    /// Returns false on timeout.
    @discardableResult
    static func recordClosedBeforeExit(_ ids: [UUID], in store: any ClosedRecordStore,
                                       timeout: TimeInterval = 2) -> Bool {
        guard !ids.isEmpty else { return true }
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await recordClosed(ids, in: store)
            done.signal()
        }
        return done.wait(timeout: .now() + timeout) == .success
    }
}

import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

/// Quick Access panels open at quit are recorded as closed (#103).
@Suite("Quick Access quit path")
struct QuickAccessQuitTests {
    /// Logs the IDs marked closed; `failing` throws for one of them.
    actor FakeStore: ClosedRecordStore {
        private(set) var closed: [UUID] = []
        let failing: UUID?

        init(failing: UUID? = nil) {
            self.failing = failing
        }

        func recordClosed(id: UUID) async throws {
            if id == failing { throw HistoryError.recordNotFound(id) }
            closed.append(id)
        }
    }

    /// Calls the blocking variant from a plain thread, as `applicationWillTerminate` does from main.
    /// Blocking a Swift concurrency pool thread instead can starve the task it waits for. The long
    /// timeout absorbs a busy parallel test run; at quit the pool is idle.
    private func blockingRecord(_ ids: [UUID], in store: any ClosedRecordStore) async -> Bool {
        await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                continuation.resume(returning: QuickAccessQuit.recordClosedBeforeExit(ids, in: store, timeout: 60))
            }
        }
    }

    @Test func marksEveryOpenPanelOldestFirst() async {
        let ids = [UUID(), UUID(), UUID()] // newest first, as Quick Access stacks them
        let store = FakeStore()
        await QuickAccessQuit.recordClosed(ids, in: store)
        #expect(await store.closed == ids.reversed())
    }

    @Test func oneFailureDoesNotStopTheRest() async {
        let ids = [UUID(), UUID(), UUID()]
        let store = FakeStore(failing: ids[1])
        await QuickAccessQuit.recordClosed(ids, in: store)
        #expect(await store.closed == [ids[2], ids[0]])
    }

    @Test func duplicatesAreMarkedOnce() async {
        let id = UUID()
        let store = FakeStore()
        await QuickAccessQuit.recordClosed([id, id], in: store)
        #expect(await store.closed == [id])
    }

    @Test func blockingVariantFinishesBeforeReturning() async {
        let ids = [UUID(), UUID()]
        let store = FakeStore()
        #expect(await blockingRecord(ids, in: store))
        #expect(await store.closed == ids.reversed())
        #expect(await blockingRecord([], in: store))
    }

    /// End to end with the real store: after "quit", Restore Recently Closed finds the newest panel.
    @Test func realStoreRestoresTheNewestPanelAfterQuit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("quit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory, retentionDays: nil)
        let image = try #require(CaptureLogicTests.solidImage(width: 4, height: 4))
        let older = try await store.add(image: image, kind: .area)
        let newer = try await store.add(image: image, kind: .area)
        #expect(await store.recentlyClosed().isEmpty)

        #expect(await blockingRecord([newer.id, older.id], in: store))

        let reopened = try HistoryStore(directory: directory, retentionDays: nil)
        #expect(await reopened.recentlyClosed().map(\.id) == [newer.id, older.id])
    }
}

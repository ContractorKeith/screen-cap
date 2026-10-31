import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

/// Lowering "Keep captures for" confirms before purging (#101).
@Suite("Retention change confirmation")
struct RetentionChangeTests {
    @Test func shorterWindowThatDeletesAsksWithTheCount() {
        let decision = RetentionChange.decide(from: 30, to: 1, expiring: 12)
        guard case let .confirm(change) = decision else {
            Issue.record("Expected a confirmation, got \(decision)")
            return
        }
        #expect(change.title == "Delete 12 captures older than 1 day?")
        #expect(change.message.contains("1 day instead of 30 days"))
        #expect(RetentionChange(current: 14, proposed: 7, count: 1).title == "Delete 1 capture older than 7 days?")
    }

    @Test func cancelRevertsAndConfirmApplies() {
        let change = RetentionChange(current: 30, proposed: 7, count: 3)
        #expect(change.resolve(confirmed: false) == 30)
        #expect(change.resolve(confirmed: true) == 7)
    }

    @Test func nothingToDeleteOrLongerWindowAppliesAtOnce() {
        #expect(RetentionChange.decide(from: 30, to: 1, expiring: 0) == .apply(1))
        #expect(RetentionChange.decide(from: 7, to: 90, expiring: 5) == .apply(90))
        #expect(RetentionChange.decide(from: 7, to: 7, expiring: 5) == .apply(7))
    }

    @Test func storeCountsWhatAPurgeWouldDelete() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("retention-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestClock(Date(timeIntervalSince1970: 1_000_000))
        let store = try HistoryStore(directory: directory, retentionDays: nil, now: { clock.now })
        let image = try #require(CaptureLogicTests.solidImage(width: 4, height: 4))
        try await store.add(image: image, kind: .area)
        try await store.add(image: image, kind: .area)
        clock.now = clock.now.addingTimeInterval(3 * 86_400)
        try await store.add(image: image, kind: .area)

        #expect(await store.count(olderThan: 1) == 2)
        #expect(await store.count(olderThan: 7) == 0)
        // Counting deletes nothing; the purge removes exactly that many.
        #expect(await store.records().count == 3)
        #expect(try await store.purge(olderThan: 1).count == 2)
    }

    final class TestClock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }
}

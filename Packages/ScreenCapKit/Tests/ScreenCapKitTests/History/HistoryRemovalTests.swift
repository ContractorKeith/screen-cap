import Foundation
@testable import ScreenCapKit
import Testing

@Suite("History removal failures")
struct HistoryRemovalTests {
    private let manager = FileManager.default

    @Test(arguments: [false, true])
    func lockedDeleteKeepsRecord(thumbnail: Bool) async throws {
        let directory = try HistoryFixtures.tempDirectory()
        defer { try? manager.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory, retentionDays: nil)
        let record = try await store.add(image: HistoryFixtures.image(width: 4, height: 4), kind: .area)
        let locked = thumbnail ? record.thumbnailURL : record.fileURL
        try manager.setAttributes([.immutable: true], ofItemAtPath: locked.path)
        defer { try? manager.setAttributes([.immutable: false], ofItemAtPath: locked.path) }

        await #expect(throws: HistoryError.filesNotRemoved(paths: [locked.path], removedIDs: [])) {
            try await store.delete(id: record.id)
        }
        #expect(manager.fileExists(atPath: locked.path))
        #expect(await store.record(id: record.id)?.isDeleted == false)
        let reopened = try HistoryStore(directory: directory, retentionDays: nil)
        #expect(await reopened.records().map(\.id) == [record.id])
        try manager.setAttributes([.immutable: false], ofItemAtPath: locked.path)
        #expect(try await store.delete(id: record.id).isDeleted)
    }

    @Test func purgeSkipsLockedAndPersistsSuccessfulRemovals() async throws {
        let directory = try HistoryFixtures.tempDirectory()
        defer { try? manager.removeItem(at: directory) }
        let clock = TestClock()
        let store = try HistoryStore(directory: directory, retentionDays: nil, now: clock.function)
        let locked = try await store.add(image: HistoryFixtures.image(width: 4, height: 4), kind: .area)
        let removable = try await store.add(image: HistoryFixtures.image(width: 4, height: 4), kind: .window)
        let missing = try await store.add(image: HistoryFixtures.image(width: 4, height: 4), kind: .area)
        try manager.removeItem(at: missing.fileURL)
        try manager.removeItem(at: missing.thumbnailURL)
        try manager.setAttributes([.immutable: true], ofItemAtPath: locked.fileURL.path)
        defer { try? manager.setAttributes([.immutable: false], ofItemAtPath: locked.fileURL.path) }
        clock.advance(seconds: 2 * 86_400)

        await #expect(throws: HistoryError.filesNotRemoved(
            paths: [locked.fileURL.path], removedIDs: [removable.id, missing.id]
        )) { try await store.purge(olderThan: 1) }
        #expect(!manager.fileExists(atPath: removable.fileURL.path))
        let reopened = try HistoryStore(directory: directory, retentionDays: nil)
        #expect(await reopened.records().map(\.id) == [locked.id])
        // Startup and read-time retention must preserve the failed record too.
        let reported = Failures()
        let automatic = try HistoryStore(directory: directory, retentionDays: 1, now: clock.function,
                                         onRemovalFailure: { reported.append($0) })
        #expect(reported.values == [.filesNotRemoved(paths: [locked.fileURL.path], removedIDs: [])])
        #expect(await automatic.records().map(\.id) == [locked.id])
        #expect(await automatic.record(id: locked.id) != nil)
        #expect(reported.values.count == 3)
        let persisted = try HistoryStore(directory: directory, retentionDays: nil)
        #expect(await persisted.records().map(\.id) == [locked.id])
    }

    private final class Failures: @unchecked Sendable {
        private let lock = NSLock()
        private var errors: [HistoryError] = []
        var values: [HistoryError] { lock.withLock { errors } }
        func append(_ error: HistoryError) { lock.withLock { errors.append(error) } }
    }

    @Test func alreadyMissingFilesCountAsDeleted() async throws {
        let directory = try HistoryFixtures.tempDirectory()
        defer { try? manager.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory, retentionDays: nil)
        let record = try await store.add(image: HistoryFixtures.image(width: 4, height: 4), kind: .area)
        try manager.removeItem(at: record.fileURL)
        try manager.removeItem(at: record.thumbnailURL)
        #expect(try await store.delete(id: record.id).isDeleted)
        #expect(await store.records().isEmpty)
    }
}

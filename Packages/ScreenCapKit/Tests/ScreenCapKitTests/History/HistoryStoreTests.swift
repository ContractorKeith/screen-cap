import CoreGraphics
import Foundation
import ImageIO
@testable import ScreenCapKit
import Testing

@Suite("HistoryStore")
struct HistoryStoreTests {
    private let fileManager = FileManager.default

    private func makeStore(_ dir: URL, clock: TestClock, retentionDays: Int? = 30) throws -> HistoryStore {
        try HistoryStore(directory: dir, retentionDays: retentionDays, now: clock.function)
    }

    @Test func addWritesFilesAndListsNewestFirst() async throws {
        let dir = try HistoryFixtures.tempDirectory()
        defer { try? fileManager.removeItem(at: dir) }
        let clock = TestClock()
        let store = try makeStore(dir, clock: clock)

        let first = try await store.add(
            image: HistoryFixtures.image(width: 1024, height: 512), kind: .area,
            metadata: CaptureMetadata(scale: 2, appName: "Safari", windowTitle: "Docs")
        )
        clock.advance(seconds: 5)
        let second = try await store.add(image: HistoryFixtures.image(width: 100, height: 50), kind: .window)

        #expect(first.pixelWidth == 1024 && first.pixelHeight == 512 && first.scale == 2)
        #expect(first.fileURL.lastPathComponent == "\(first.id.uuidString).png")
        #expect(first.thumbnailURL.lastPathComponent == "\(first.id.uuidString)-thumb.png")
        #expect(fileManager.fileExists(atPath: first.fileURL.path))
        let thumbSource = try #require(CGImageSourceCreateWithURL(first.thumbnailURL as CFURL, nil))
        let thumb = try #require(CGImageSourceCreateImageAtIndex(thumbSource, 0, nil))
        #expect(thumb.width == 256 && thumb.height == 128)
        #expect(await store.records().map(\.id) == [second.id, first.id])

        // Reopening reads the same index from disk.
        let reopened = try makeStore(dir, clock: clock)
        #expect(await reopened.records() == [second, first])
    }

    @Test func filterByKind() async throws {
        let dir = try HistoryFixtures.tempDirectory()
        defer { try? fileManager.removeItem(at: dir) }
        let store = try makeStore(dir, clock: TestClock())
        let image = HistoryFixtures.image(width: 10, height: 10)
        let area = try await store.add(image: image, kind: .area)
        let scroll = try await store.add(image: image, kind: .scrolling)

        #expect(await store.records(filter: .area).map(\.id) == [area.id])
        #expect(await store.records(filter: .scrolling).map(\.id) == [scroll.id])
        #expect(await store.records(filter: .pinnedImport).isEmpty)
    }

    @Test func searchIsCaseInsensitiveOverOCRAppAndTitle() async throws {
        let dir = try HistoryFixtures.tempDirectory()
        defer { try? fileManager.removeItem(at: dir) }
        let store = try makeStore(dir, clock: TestClock())
        let image = HistoryFixtures.image(width: 10, height: 10)
        let invoice = try await store.add(image: image, kind: .area, metadata: CaptureMetadata(appName: "Preview"))
        let other = try await store.add(image: image, kind: .window, metadata: CaptureMetadata(windowTitle: "Terminal"))
        try await store.setOCRText(id: invoice.id, text: "Invoice #42\nTotal DUE")

        #expect(await store.records(query: "total due").map(\.id) == [invoice.id])
        #expect(await store.records(query: "PREVIEW").map(\.id) == [invoice.id])
        #expect(await store.records(query: "termin").map(\.id) == [other.id])
        #expect(await store.records(query: "  ").count == 2)
        #expect(await store.records(filter: .window, query: "invoice").isEmpty)
    }

    @Test func markClosedRecentlyClosedRestore() async throws {
        let dir = try HistoryFixtures.tempDirectory()
        defer { try? fileManager.removeItem(at: dir) }
        let clock = TestClock()
        let store = try makeStore(dir, clock: clock)
        let image = HistoryFixtures.image(width: 10, height: 10)
        let first = try await store.add(image: image, kind: .area)
        let second = try await store.add(image: image, kind: .area)
        _ = try await store.add(image: image, kind: .area)

        try await store.markClosed(id: second.id)
        clock.advance(seconds: 1)
        let closed = try await store.markClosed(id: first.id)
        #expect(closed.closedAt == clock.now)
        #expect(await store.recentlyClosed(limit: 10).map(\.id) == [first.id, second.id])
        #expect(await store.recentlyClosed(limit: 1).map(\.id) == [first.id])

        let restored = try await store.restore(id: first.id)
        #expect(restored.closedAt == nil)
        #expect(await store.recentlyClosed().map(\.id) == [second.id])
        #expect(await store.records().count == 3)
    }

    @Test func deleteRemovesBothFiles() async throws {
        let dir = try HistoryFixtures.tempDirectory()
        defer { try? fileManager.removeItem(at: dir) }
        let store = try makeStore(dir, clock: TestClock())
        let record = try await store.add(image: HistoryFixtures.image(width: 300, height: 300), kind: .fullscreen)

        let deleted = try await store.delete(id: record.id)
        #expect(deleted.isDeleted)
        #expect(!fileManager.fileExists(atPath: record.fileURL.path))
        #expect(!fileManager.fileExists(atPath: record.thumbnailURL.path))
        #expect(await store.records().isEmpty)
        #expect(try await makeStore(dir, clock: TestClock()).records().isEmpty)
        await #expect(throws: HistoryError.recordNotFound(record.id)) { try await store.delete(id: record.id) }
    }

    @Test func purgeRemovesOnlyOldRecords() async throws {
        let dir = try HistoryFixtures.tempDirectory()
        defer { try? fileManager.removeItem(at: dir) }
        let clock = TestClock()
        let store = try makeStore(dir, clock: clock)
        let image = HistoryFixtures.image(width: 10, height: 10)
        let old = try await store.add(image: image, kind: .area)
        clock.advance(days: 20)
        let recent = try await store.add(image: image, kind: .area)
        clock.advance(days: 11)

        #expect(try await store.purge(olderThan: 30) == [old.id])
        #expect(await store.records().map(\.id) == [recent.id])
        #expect(!fileManager.fileExists(atPath: old.fileURL.path))
        #expect(!fileManager.fileExists(atPath: old.thumbnailURL.path))
        #expect(fileManager.fileExists(atPath: recent.fileURL.path))
    }

    @Test func autoPurgeRunsOnLoad() async throws {
        let dir = try HistoryFixtures.tempDirectory()
        defer { try? fileManager.removeItem(at: dir) }
        let clock = TestClock()
        let old = try await makeStore(dir, clock: clock)
            .add(image: HistoryFixtures.image(width: 10, height: 10), kind: .area)
        clock.advance(days: 31)

        let reopened = try makeStore(dir, clock: clock)
        #expect(await reopened.records().isEmpty)
        #expect(!fileManager.fileExists(atPath: old.fileURL.path))
    }

    @Test func corruptIndexIsSetAsideAndRebuiltFromDisk() async throws {
        let dir = try HistoryFixtures.tempDirectory()
        defer { try? fileManager.removeItem(at: dir) }
        let clock = TestClock()
        let record = try await makeStore(dir, clock: clock)
            .add(image: HistoryFixtures.image(width: 640, height: 320), kind: .window)
        try fileManager.removeItem(at: record.thumbnailURL)
        try Data("{ not json".utf8).write(to: dir.appendingPathComponent(HistoryStore.indexFileName))
        try Data("x".utf8).write(to: dir.appendingPathComponent("notes.png"))

        let rebuilt = try makeStore(dir, clock: clock)
        let records = await rebuilt.records()
        #expect(records.count == 1)
        let only = try #require(records.first)
        #expect(only.id == record.id)
        #expect(only.kind == .unknown)
        #expect(only.pixelWidth == 640 && only.pixelHeight == 320)
        #expect(fileManager.fileExists(atPath: only.thumbnailURL.path))

        let stamp = Int(clock.now.timeIntervalSince1970)
        #expect(fileManager.fileExists(atPath: dir.appendingPathComponent("index.json.corrupt-\(stamp)").path))
        // The rebuilt index is valid on the next open.
        #expect(try await makeStore(dir, clock: clock).records().map(\.id) == [record.id])
    }

    @Test func storageSizeMatchesFileSizes() async throws {
        let dir = try HistoryFixtures.tempDirectory()
        defer { try? fileManager.removeItem(at: dir) }
        let store = try makeStore(dir, clock: TestClock())
        let first = try await store.add(image: HistoryFixtures.image(width: 800, height: 600), kind: .area)
        let second = try await store.add(image: HistoryFixtures.image(width: 50, height: 50), kind: .text)

        let expected = try [first.fileURL, first.thumbnailURL, second.fileURL, second.thumbnailURL]
            .map { try fileManager.attributesOfItem(atPath: $0.path)[.size] as? Int64 ?? -1 }
            .reduce(0, +)
        #expect(expected > 0)
        #expect(await store.storageSize() == expected)
    }

    @Test func unknownKindsRoundTrip() throws {
        let data = Data(#""screen-recording""#.utf8)
        let kind = try JSONDecoder().decode(CaptureKind.self, from: data)
        #expect(kind.rawValue == "screen-recording")
        #expect(try JSONEncoder().encode(kind) == data)
    }

    @Test func unknownIDThrows() async throws {
        let dir = try HistoryFixtures.tempDirectory()
        defer { try? fileManager.removeItem(at: dir) }
        let store = try makeStore(dir, clock: TestClock())
        let id = UUID()
        await #expect(throws: HistoryError.recordNotFound(id)) { try await store.markClosed(id: id) }
    }
}

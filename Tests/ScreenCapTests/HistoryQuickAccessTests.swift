import AppKit
import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

/// #41 (files and records into Quick Access) and #53 (OCR text reaches history).
@Suite("History ↔ Quick Access and OCR")
@MainActor
struct HistoryQuickAccessTests {
    private func makeStore() throws -> (HistoryStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString)")
        return (try HistoryStore(directory: directory, retentionDays: nil), directory)
    }

    // MARK: - #41

    @Test func recordIDLoadsTheRecordWithoutClearingClosed() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try #require(HistoryViewModelTests.image())
        let record = try await store.add(image: image, kind: .window, metadata: CaptureMetadata(appName: "Notes"))
        try await store.markClosed(id: record.id)

        let result = try #require(await QuickAccessSource.result(url: nil, recordID: record.id, history: store))
        #expect(result.historyRecordID == record.id)
        #expect(result.kind == .window)
        #expect(result.context.app == "Notes")
        #expect(result.image.cgImage.width == 4)
        // Loading alone doesn't drop it from Restore Recently Closed; the controller restores after show.
        #expect(await store.recentlyClosed().map(\.id) == [record.id])
    }

    @Test func fileInHistoryMatchesItsRecord() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = try await store.add(image: try #require(HistoryViewModelTests.image()), kind: .area)
        let result = await QuickAccessSource.result(url: record.fileURL, recordID: nil, history: store)
        #expect(result?.historyRecordID == record.id)
        #expect(await store.records().count == 1)
    }

    @Test func outsideFileIsImportedIntoHistory() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("outside.png")
        try Exporter(image: try #require(HistoryViewModelTests.image()), format: .png, scale: 1).data().write(to: file)

        let result = try #require(await QuickAccessSource.result(url: file, recordID: nil, history: store))
        let records = await store.records()
        #expect(records.map(\.kind) == [.pinnedImport])
        #expect(result.historyRecordID == records.first?.id)
    }

    @Test func unreadableFileGivesNothing() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("missing.png")
        #expect(await QuickAccessSource.result(url: missing, recordID: nil, history: store) == nil)
        #expect(await QuickAccessSource.result(url: missing, recordID: UUID(), history: nil) == nil)
        #expect(await store.records().isEmpty)
    }

    // MARK: - #53

    @Test func textRequestCarriesRecordIDFromKeyOrResult() throws {
        let id = UUID()
        #expect(TextCaptureController.request(from: ["recordID": id]).recordID == id)

        let image = try #require(HistoryViewModelTests.image())
        let result = QuickAccessItem.result(image: image, scale: 1, kind: .area,
                                            context: FilenameTemplate.Context(), recordID: id)
        let quickAccess = TextCaptureController.request(from: ["image": image, "result": result])
        #expect(quickAccess.recordID == id)
        #expect(quickAccess.image != nil)

        let rect = CGRect(x: 1, y: 2, width: 3, height: 4)
        let fresh = TextCaptureController.request(from: ["rect": NSValue(rect: rect)])
        #expect(fresh.rect == rect)
        #expect(fresh.recordID == nil)
    }

    @Test func freshTextGrabBecomesSearchableTextRecord() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try #require(HistoryViewModelTests.image())
        let captured = CapturedImage(cgImage: image, scale: 2, pointRect: CGRect(x: 0, y: 0, width: 2, height: 2),
                                     displayID: nil)

        let id = try #require(await TextCaptureController.addTextRecord(captured, to: store))
        await TextCaptureController.storeText("Hello Zebra", recordID: id, in: store)

        let model = HistoryViewModel(store: store, retentionDays: { 30 })
        await model.reload()
        model.query = "zebra"
        #expect(model.visible.map(\.id) == [id])
        model.query = ""
        model.kindFilter = .text
        #expect(model.visible.map(\.id) == [id])
        #expect(await TextCaptureController.addTextRecord(captured, to: nil) == nil)
    }
}

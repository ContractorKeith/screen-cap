import CoreGraphics
import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

@Suite("History view model")
@MainActor
struct HistoryViewModelTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(_ kind: HistoryKind, daysAgo: Double, ocr: String? = nil, app: String? = nil,
                        window: String? = nil, closed: Bool = false) -> CaptureRecord {
        let url = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).png")
        return CaptureRecord(kind: kind, createdAt: Self.now.addingTimeInterval(-daysAgo * 86_400),
                             pixelWidth: 10, pixelHeight: 10, fileURL: url, thumbnailURL: url,
                             ocrText: ocr, appName: app, windowTitle: window,
                             closedAt: closed ? Self.now : nil)
    }

    private func filter(_ records: [CaptureRecord], kind: HistoryKind? = nil, query: String = "",
                        days: Int = 30) -> [CaptureRecord] {
        HistoryViewModel.filter(records, kind: kind, query: query, retentionDays: days, now: Self.now)
    }

    @Test func newestFirstWithinRetention() {
        let old = record(.area, daysAgo: 31)
        let mid = record(.area, daysAgo: 5)
        let new = record(.window, daysAgo: 1)
        #expect(filter([old, mid, new]).map(\.id) == [new.id, mid.id])
        #expect(filter([old, mid, new], days: 2).map(\.id) == [new.id])
    }

    @Test func filtersByKind() {
        let area = record(.area, daysAgo: 1)
        let window = record(.window, daysAgo: 2)
        let text = record(.text, daysAgo: 3)
        #expect(filter([area, window, text], kind: .window).map(\.id) == [window.id])
        #expect(filter([area, window, text], kind: .scrolling).isEmpty)
        #expect(filter([area, window, text]).count == 3)
    }

    @Test func searchesOCRAppAndWindowCaseAndDiacriticInsensitive() {
        let receipt = record(.text, daysAgo: 1, ocr: "Total €42 Café")
        let safari = record(.window, daysAgo: 2, app: "Safari", window: "Pull Request #28")
        let none = record(.area, daysAgo: 3)
        let all = [receipt, safari, none]
        #expect(filter(all, query: "cafe").map(\.id) == [receipt.id])
        #expect(filter(all, query: "SAFARI").map(\.id) == [safari.id])
        #expect(filter(all, query: "request #28").map(\.id) == [safari.id])
        #expect(filter(all, query: "   ").count == 3)
        #expect(filter(all, query: "missing").isEmpty)
        #expect(filter(all, kind: .text, query: "safari").isEmpty)
    }

    @Test func skipsDeletedRecords() {
        var deleted = record(.area, daysAgo: 1)
        deleted.isDeleted = true
        #expect(filter([deleted]).isEmpty)
    }

    @Test func clickSelectsOneAndCommandClickToggles() {
        let first = UUID()
        let second = UUID()
        #expect(HistoryViewModel.select(first, in: [second], toggling: false) == [first])
        #expect(HistoryViewModel.select(first, in: [second], toggling: true) == [first, second])
        #expect(HistoryViewModel.select(first, in: [first, second], toggling: true) == [second])
    }

    @Test func restoreNeedsAClosedRecord() {
        #expect(!HistoryViewModel.canRestore([record(.area, daysAgo: 1)]))
        #expect(HistoryViewModel.canRestore([record(.area, daysAgo: 1), record(.area, daysAgo: 1, closed: true)]))
    }

    @Test func storeBackedDeleteRestoreAndPurge() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = try HistoryStore(directory: directory, retentionDays: nil, now: { clock.now })
        let image = try #require(Self.image())
        let old = try await store.add(image: image, kind: .area)
        clock.now = Self.now
        let kept = try await store.add(image: image, kind: .window, metadata: CaptureMetadata(appName: "Notes"))
        try await store.markClosed(id: kept.id)

        let model = HistoryViewModel(store: store, retentionDays: { 30 }, now: { Self.now })
        await model.reload()
        #expect(model.records.count == 2)
        #expect(model.visible.map(\.id) == [kept.id])
        #expect(model.storageBytes > 0)

        model.selection = [kept.id]
        #expect(model.canRestore)
        #expect(model.restorable([kept.id, old.id]).map(\.id) == [kept.id])
        // Quick Access clears closedAt only after the panel is shown (#41).
        #expect(await store.recentlyClosed().map(\.id) == [kept.id])
        try await store.restore(id: kept.id)
        await model.reload()
        #expect(!model.canRestore)

        await model.purge()
        #expect(model.records.map(\.id) == [kept.id])

        await model.delete([kept.id])
        #expect(model.records.isEmpty)
        #expect(model.selection.isEmpty)
    }

    /// Mutable clock for the store; the first record is created 40 days before `now`.
    final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_800_000_000 - 40 * 86_400)
    }

    static func image() -> CGImage? {
        let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return context?.makeImage()
    }
}

import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

@Suite("History removal failure HUDs")
@MainActor
struct HistoryRemovalHUDTests {
    @Test func callersReportLockedCaptureAndKeepItVisible() async throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("history-removal-\(UUID())")
        defer { try? manager.removeItem(at: directory) }
        let old = Date().addingTimeInterval(-40 * 86_400)
        let writer = try HistoryStore(directory: directory, retentionDays: nil, now: { old })
        let record = try await writer.add(image: #require(HistoryViewModelTests.image()), kind: .area)
        let store = try HistoryStore(directory: directory, retentionDays: nil)
        try manager.setAttributes([.immutable: true], ofItemAtPath: record.fileURL.path)
        defer { try? manager.setAttributes([.immutable: false], ofItemAtPath: record.fileURL.path) }
        let sentence = HistoryError.filesNotRemoved(paths: [record.fileURL.path], removedIDs: []).localizedDescription
        var messages: [String] = []
        let model = HistoryViewModel(store: store, retentionDays: { 30 }, showFailure: { messages.append($0) })
        await model.delete([record.id])
        #expect(messages == [sentence])
        #expect(model.visible.map(\.id) == [record.id])
        await model.purge()
        #expect(messages == [sentence, sentence])
        #expect(model.visible.map(\.id) == [record.id])

        let message = await QuickAccessDeletion.run(deleteRecord: {
            try await store.delete(id: record.id)
        }, fileURL: nil, trash: { _ in Issue.record("No saved file to trash") })
        #expect(message?.contains(sentence) == true)

        let settings = AppSettings(store: InMemorySettingsStore())
        let retention = HistoryRetention(store: store, settings: settings, showFailure: { messages.append($0) })
        retention.start()
        defer { retention.stop() }
        await retention.settled()
        #expect(messages == [sentence, sentence, sentence])
        #expect(await store.records().map(\.id) == [record.id])
    }
}

import AppKit
import Observation
import ScreenCapKit

/// State behind the History window: loaded records, filter, search and selection.
/// The filtering and selection rules are static and pure so they are unit-tested.
@MainActor
@Observable
final class HistoryViewModel {
    /// Kinds offered in the filter menu, in order.
    static let filterKinds: [HistoryKind] = [.area, .window, .fullscreen, .scrolling, .text]

    private(set) var records: [CaptureRecord] = []
    private(set) var storageBytes: Int64 = 0
    /// nil shows every kind.
    var kindFilter: HistoryKind?
    var query = ""
    var selection: Set<UUID> = []

    @ObservationIgnored private let store: HistoryStore?
    @ObservationIgnored private let retentionDays: @MainActor () -> Int
    @ObservationIgnored private let now: () -> Date

    init(store: HistoryStore?, retentionDays: @escaping @MainActor () -> Int, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.retentionDays = retentionDays
        self.now = now
    }

    var isAvailable: Bool { store != nil }

    /// Records matching the filter and search, newest first.
    var visible: [CaptureRecord] {
        Self.filter(records, kind: kindFilter, query: query, retentionDays: retentionDays(), now: now())
    }

    var selectedRecords: [CaptureRecord] {
        visible.filter { selection.contains($0.id) }
    }

    /// True when any selected record had its Quick Access overlay closed.
    var canRestore: Bool { Self.canRestore(selectedRecords) }

    // MARK: - Pure rules

    /// Not deleted, within the retention window, of `kind` (nil = all), matching `query`
    /// over OCR text, app name and window title (case- and diacritic-insensitive). Newest first.
    static func filter(_ records: [CaptureRecord], kind: HistoryKind?, query: String, retentionDays: Int,
                       now: Date) -> [CaptureRecord] {
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return records
            .filter { !$0.isDeleted && $0.createdAt >= cutoff }
            .filter { kind == nil || $0.kind == kind }
            .filter { trimmed.isEmpty || matches($0, query: trimmed) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func matches(_ record: CaptureRecord, query: String) -> Bool {
        [record.ocrText, record.appName, record.windowTitle].contains { field in
            field?.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// A click selects only `id`; ⌘-click (`toggling`) adds or removes it.
    static func select(_ id: UUID, in selection: Set<UUID>, toggling: Bool) -> Set<UUID> {
        guard toggling else { return [id] }
        return selection.symmetricDifference([id])
    }

    static func canRestore(_ records: [CaptureRecord]) -> Bool {
        records.contains { $0.closedAt != nil }
    }

    static func title(for kind: HistoryKind) -> String {
        switch kind {
        case .area: "Area"
        case .window: "Window"
        case .fullscreen: "Fullscreen"
        case .scrolling: "Scrolling"
        case .text: "Text"
        case .pinnedImport: "Pinned"
        default: kind.rawValue.capitalized
        }
    }

    // MARK: - Store

    func reload() async {
        guard let store else { return }
        records = await store.records()
        storageBytes = await store.storageSize()
        selection.formIntersection(Set(records.map(\.id)))
    }

    func delete(_ ids: Set<UUID>) async {
        guard let store else { return }
        for id in ids {
            do { try await store.delete(id: id) } catch { log("delete", error) }
        }
        TempFiles.shared.release(records: ids) // temp copies of deleted captures (#114)
        await reload()
    }

    /// The closed records among `ids`, for Restore to Quick Access. Doesn't touch the store:
    /// Quick Access clears `closedAt` once the panel is on screen, so a failed restore stays in
    /// Restore Recently Closed.
    func restorable(_ ids: Set<UUID>) -> [CaptureRecord] {
        records.filter { ids.contains($0.id) && $0.closedAt != nil }
    }

    /// Deletes everything older than the retention setting.
    func purge() async {
        guard let store else { return }
        do {
            let removed = try await store.purge(olderThan: retentionDays())
            TempFiles.shared.release(records: removed) // #114
        } catch { log("purge", error) }
        await reload()
    }

    private func log(_ verb: String, _ error: Error) {
        appLog.error("History \(verb, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    }
}

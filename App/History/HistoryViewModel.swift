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
    /// The keyboard cursor (#130): where arrow keys move from and what Return opens.
    var cursor: UUID?

    @ObservationIgnored private let store: HistoryStore?
    @ObservationIgnored private let retentionDays: @MainActor () -> Int
    @ObservationIgnored private let showFailure: (String) -> Void

    init(store: HistoryStore?, retentionDays: @escaping @MainActor () -> Int,
         showFailure: @escaping (String) -> Void = { HUDPanel.show($0, duration: .seconds(6)) }) {
        self.store = store
        self.retentionDays = retentionDays
        self.showFailure = showFailure
    }

    var isAvailable: Bool { store != nil }

    /// Records matching the filter and search, newest first.
    var visible: [CaptureRecord] {
        Self.filter(records, kind: kindFilter, query: query)
    }

    var selectedRecords: [CaptureRecord] {
        visible.filter { selection.contains($0.id) }
    }

    /// The record Return and Space act on: the cursor if selected, else the first selected.
    var focusedRecord: CaptureRecord? {
        let visible = visible
        if let cursor, selection.contains(cursor), let record = visible.first(where: { $0.id == cursor }) {
            return record
        }
        return visible.first { selection.contains($0.id) }
    }

    /// Arrow-key move through the grid (#130). Without `extending` it selects only the new cell;
    /// with ⇧ it adds the new cell to the selection. Returns the new cursor for scrolling.
    @discardableResult
    func moveCursor(_ direction: GridMove, columns: Int, extending: Bool) -> UUID? {
        guard let id = Self.moveCursor(in: visible.map(\.id), from: cursor, direction, columns: columns) else {
            return nil
        }
        cursor = id
        selection = Self.selecting(id, in: selection, extending: extending)
        return id
    }

    /// True when any selected record had its Quick Access overlay closed.
    var canRestore: Bool { Self.canRestore(selectedRecords) }

    // MARK: - Pure rules

    /// Not deleted, of `kind` (nil = all), matching `query`. The store enforces retention,
    /// keeping captures it could not delete available for retry. Searches are
    /// over OCR text, app name and window title (case- and diacritic-insensitive). Newest first.
    static func filter(_ records: [CaptureRecord], kind: HistoryKind?, query: String) -> [CaptureRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return records
            .filter { !$0.isDeleted }
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

    enum GridMove: Sendable { case left, right, above, below }

    /// The cursor after an arrow-key move over `ids` (grid order). Nil when there are none.
    nonisolated static func moveCursor(in ids: [UUID], from cursor: UUID?, _ direction: GridMove,
                                       columns: Int) -> UUID? {
        let current = cursor.flatMap { ids.firstIndex(of: $0) }
        return move(from: current, direction, columns: columns, count: ids.count).map { ids[$0] }
    }

    /// Arrow keys select just the new cell; ⇧-arrows add it.
    nonisolated static func selecting(_ id: UUID, in selection: Set<UUID>, extending: Bool) -> Set<UUID> {
        extending ? selection.union([id]) : [id]
    }

    /// Index after an arrow-key move in a row-major grid of `columns` and `count` cells.
    /// No cursor yet lands on the first cell. Left/right stop at the ends; above/below move a row and
    /// stay put at the top or bottom row. Down into a shorter last row lands on its last cell.
    nonisolated static func move(from index: Int?, _ direction: GridMove, columns: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let index, index < count else { return 0 }
        let columns = max(1, columns)
        switch direction {
        case .left: return max(0, index - 1)
        case .right: return min(count - 1, index + 1)
        case .above: return index >= columns ? index - columns : index
        case .below:
            let lastRow = (count - 1) / columns
            guard index / columns < lastRow else { return index }
            return min(count - 1, index + columns)
        }
    }

    /// How many columns `LazyVGrid`'s adaptive layout fits in `width`: as many `minimum`-wide
    /// cells with `spacing` between them as fit, at least one.
    nonisolated static func columnCount(width: CGFloat, minimum: CGFloat, spacing: CGFloat) -> Int {
        guard width > 0 else { return 1 }
        return max(1, Int(((width + spacing) / (minimum + spacing)).rounded(.down)))
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
        if let cursor, !records.contains(where: { $0.id == cursor }) { self.cursor = nil }
    }

    func delete(_ ids: Set<UUID>) async {
        guard let store else { return }
        var removed: [UUID] = []
        for id in ids {
            do {
                try await store.delete(id: id)
                removed.append(id)
            } catch { log("delete", error) }
        }
        TempFiles.shared.release(records: removed) // temp copies of deleted captures (#114)
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
        if case let HistoryError.filesNotRemoved(_, removed) = error {
            TempFiles.shared.release(records: removed)
        }
        showFailure(error.localizedDescription)
        appLog.error("History \(verb, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    }
}

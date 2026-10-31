import CoreGraphics
import Foundation
import ImageIO

/// Errors from the capture history store.
public enum HistoryError: Error, Equatable {
    case recordNotFound(UUID)
    case thumbnailFailed
}

/// On-disk capture history (PLAN §3.4): `<id>.png`, `<id>-thumb.png` and an `index.json`
/// in one directory. The index is loaded once at init and kept in memory; every mutation
/// rewrites it atomically, serialized by the actor.
public actor HistoryStore {
    public static let indexFileName = "index.json"
    public static let defaultRetentionDays = 30

    /// `~/Library/Application Support/ScreenCap/History`.
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScreenCap/History", isDirectory: true)
    }

    public nonisolated let directory: URL
    private let now: @Sendable () -> Date
    private var index: [CaptureRecord]
    /// Days to keep; nil keeps everything. Reads purge anything older first (#86).
    public private(set) var retentionDays: Int?

    /// Opens (or creates) the store, rebuilding a corrupt index and purging records older
    /// than `retentionDays`. Pass `retentionDays: nil` to skip the auto-purge.
    public init(
        directory: URL = HistoryStore.defaultDirectory,
        retentionDays: Int? = HistoryStore.defaultRetentionDays,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var records = try Self.loadIndex(in: directory, now: now())
        var changed = false
        if let retentionDays {
            let cutoff = Self.cutoff(days: retentionDays, now: now())
            let expired = records.filter { $0.createdAt < cutoff }
            expired.forEach(Self.removeFiles)
            records.removeAll { $0.createdAt < cutoff }
            changed = !expired.isEmpty
        }
        if changed { try Self.writeIndex(records, in: directory) }
        self.directory = directory
        self.now = now
        self.index = records
        self.retentionDays = retentionDays
    }

    // MARK: - Adding

    /// Stores `image` as `<id>.png` plus a 256px-wide `<id>-thumb.png` and indexes it.
    @discardableResult
    public func add(image: CGImage, kind: CaptureKind, metadata: CaptureMetadata = CaptureMetadata()) throws
        -> CaptureRecord {
        let id = UUID()
        let fileURL = Self.imageURL(id, in: directory)
        let thumbURL = Self.thumbnailURL(id, in: directory)
        guard let thumbnail = Thumbnailer.make(image) else { throw HistoryError.thumbnailFailed }
        do {
            try ProjectFile.writePNG(image, to: fileURL)
            try ProjectFile.writePNG(thumbnail, to: thumbURL)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: thumbURL)
            throw error
        }
        let record = CaptureRecord(
            id: id, kind: kind, createdAt: now(),
            pixelWidth: image.width, pixelHeight: image.height, scale: metadata.scale,
            fileURL: fileURL, thumbnailURL: thumbURL,
            ocrText: metadata.ocrText, appName: metadata.appName, windowTitle: metadata.windowTitle
        )
        index.append(record)
        try save()
        return record
    }

    // MARK: - Reading

    public func record(id: UUID) -> CaptureRecord? {
        purgeExpiredQuietly()
        return index.first { $0.id == id }
    }

    /// Records newest first, optionally limited to one kind and to a case-insensitive
    /// search over OCR text, app name and window title. A blank query matches everything.
    public func records(filter kind: CaptureKind? = nil, query: String? = nil) -> [CaptureRecord] {
        purgeExpiredQuietly()
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return index
            .filter { !$0.isDeleted }
            .filter { kind == nil || $0.kind == kind }
            .filter { trimmed.isEmpty || $0.matches(query: trimmed) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Captures whose Quick Access overlay was closed, most recently closed first.
    public func recentlyClosed(limit: Int = 10) -> [CaptureRecord] {
        purgeExpiredQuietly()
        return Array(
            index
                .filter { $0.closedAt != nil && !$0.isDeleted }
                .sorted { ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast) }
                .prefix(max(0, limit))
        )
    }

    /// Total bytes used by the indexed captures and thumbnails.
    public func storageSize() -> Int64 {
        index.reduce(0) { $0 + Self.size(of: $1.fileURL) + Self.size(of: $1.thumbnailURL) }
    }

    // MARK: - Updating

    @discardableResult
    public func setOCRText(id: UUID, text: String?) throws -> CaptureRecord {
        try update(id) { $0.ocrText = text }
    }

    /// Records that the capture's Quick Access overlay was dismissed.
    @discardableResult
    public func markClosed(id: UUID) throws -> CaptureRecord {
        let date = now()
        return try update(id) { $0.closedAt = date }
    }

    /// Clears `closedAt` so the capture can be shown in Quick Access again.
    @discardableResult
    public func restore(id: UUID) throws -> CaptureRecord {
        try update(id) { $0.closedAt = nil }
    }

    /// Removes the capture's files and its index entry. Returns the record with `isDeleted` set.
    @discardableResult
    public func delete(id: UUID) throws -> CaptureRecord {
        guard let position = index.firstIndex(where: { $0.id == id }) else { throw HistoryError.recordNotFound(id) }
        var record = index.remove(at: position)
        Self.removeFiles(record)
        try save()
        record.isDeleted = true
        return record
    }

    /// How many records `purge(olderThan: days)` would delete; for confirming first (#101).
    public func count(olderThan days: Int) -> Int {
        let cutoff = Self.cutoff(days: days, now: now())
        return index.count { $0.createdAt < cutoff }
    }

    /// Deletes every record created more than `days` days ago. Returns the removed IDs.
    @discardableResult
    public func purge(olderThan days: Int = HistoryStore.defaultRetentionDays) throws -> [UUID] {
        let cutoff = Self.cutoff(days: days, now: now())
        let expired = index.filter { $0.createdAt < cutoff }
        guard !expired.isEmpty else { return [] }
        expired.forEach(Self.removeFiles)
        index.removeAll { $0.createdAt < cutoff }
        try save()
        return expired.map(\.id)
    }

    /// Changes the retention window and purges right away.
    @discardableResult
    public func setRetention(days: Int?) throws -> [UUID] {
        retentionDays = days
        return try purgeExpired()
    }

    /// Deletes records older than `retentionDays` (files and index). Run periodically while the
    /// app stays open; reads also call it so expired captures never resurface.
    @discardableResult
    public func purgeExpired() throws -> [UUID] {
        guard let retentionDays else { return [] }
        return try purge(olderThan: retentionDays)
    }

    // MARK: - Private

    private func purgeExpiredQuietly() {
        do { try purgeExpired() } catch {
            // The index write failed; still hide what's expired so it can't be restored.
            if let retentionDays {
                let cutoff = Self.cutoff(days: retentionDays, now: now())
                index.removeAll { $0.createdAt < cutoff }
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout CaptureRecord) -> Void) throws -> CaptureRecord {
        guard let position = index.firstIndex(where: { $0.id == id }) else { throw HistoryError.recordNotFound(id) }
        change(&index[position])
        try save()
        return index[position]
    }

    private func save() throws {
        try Self.writeIndex(index, in: directory)
    }
}

// MARK: - Index and file helpers

extension HistoryStore {
    /// On-disk shape of `index.json`.
    private struct IndexFile: Codable {
        var version: Int
        var records: [CaptureRecord]
    }

    static func imageURL(_ id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id.uuidString).png")
    }

    static func thumbnailURL(_ id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id.uuidString)-thumb.png")
    }

    private static func cutoff(days: Int, now: Date) -> Date {
        now.addingTimeInterval(-Double(days) * 86_400)
    }

    private static func writeIndex(_ records: [CaptureRecord], in directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(IndexFile(version: 1, records: records))
        try data.write(to: directory.appendingPathComponent(indexFileName), options: .atomic)
    }

    /// Reads `index.json`. A missing index is rebuilt from disk; an unreadable one is renamed
    /// to `index.json.corrupt-<timestamp>` first so it can be inspected later.
    private static func loadIndex(in directory: URL, now: Date) throws -> [CaptureRecord] {
        let indexURL = directory.appendingPathComponent(indexFileName)
        if let data = try? Data(contentsOf: indexURL) {
            if let file = try? JSONDecoder().decode(IndexFile.self, from: data) { return file.records }
            let stamp = Int(now.timeIntervalSince1970)
            let corruptURL = directory.appendingPathComponent("\(indexFileName).corrupt-\(stamp)")
            try? FileManager.default.removeItem(at: corruptURL)
            try FileManager.default.moveItem(at: indexURL, to: corruptURL)
        }
        let records = rebuildRecords(in: directory, now: now)
        try writeIndex(records, in: directory)
        return records
    }

    /// Turns every `<uuid>.png` in `directory` into a record of unknown kind,
    /// regenerating missing thumbnails.
    private static func rebuildRecords(in directory: URL, now: Date) -> [CaptureRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey]
        )) ?? []
        return files.compactMap { url -> CaptureRecord? in
            guard url.pathExtension == "png",
                  let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return nil }
            let thumbURL = thumbnailURL(id, in: directory)
            if !FileManager.default.fileExists(atPath: thumbURL.path), let thumbnail = Thumbnailer.make(image) {
                try? ProjectFile.writePNG(thumbnail, to: thumbURL)
            }
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? now
            return CaptureRecord(
                id: id, kind: .unknown, createdAt: created,
                pixelWidth: image.width, pixelHeight: image.height,
                fileURL: url, thumbnailURL: thumbURL
            )
        }
    }

    private static func removeFiles(_ record: CaptureRecord) {
        try? FileManager.default.removeItem(at: record.fileURL)
        try? FileManager.default.removeItem(at: record.thumbnailURL)
    }

    /// Size in bytes of a file, or of everything inside a directory (project packages).
    private static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        guard values.isDirectory == true else { return Int64(values.fileSize ?? 0) }
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        var total: Int64 = 0
        while let child = enumerator?.nextObject() as? URL {
            total += Int64((try? child.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}

import Darwin
import Foundation

/// Every temp file the app writes (drag-out copies, copy-as-file, share, clipboard imports) lives
/// in a per-launch folder, `$TMPDIR/ScreenCap/launch-<pid>/`, and is tracked here so it is
/// removed as soon as it's no longer needed (#114): its panel closes, its history record is
/// deleted or expires, a newer copy replaces it on the clipboard, or the app quits. Launch
/// purges folders left by earlier runs that didn't quit cleanly.
@MainActor
final class TempFiles {
    static let shared = TempFiles(root: FileManager.default.temporaryDirectory
        .appendingPathComponent("ScreenCap", isDirectory: true))

    /// What a tracked file belongs to; releasing an owner removes its files.
    enum Owner: Hashable {
        /// One Quick Access panel, editor share or clipboard import.
        case token(UUID)
        /// The file currently on the clipboard (copy-as-file); replaced by the next copy.
        case clipboard
    }

    let root: URL
    let launchFolder: URL
    private struct Entry {
        let url: URL
        let owner: Owner
        let record: UUID?
    }

    private var entries: [Entry] = []

    init(root: URL, processID: Int32 = ProcessInfo.processInfo.processIdentifier) {
        self.root = root
        launchFolder = root.appendingPathComponent(Self.folderPrefix + String(processID), isDirectory: true)
    }

    private static let folderPrefix = "launch-"

    /// A new, empty folder inside this launch's folder, so names from the filename template
    /// never collide.
    func makeFolder() throws -> URL {
        let folder = launchFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Tracks `url` (a file or folder) under `owner`, also tied to a history record when given.
    func track(_ url: URL, owner: Owner, record: UUID? = nil) {
        entries.append(Entry(url: url, owner: owner, record: record))
    }

    /// Removes every file `owner` holds.
    func release(_ owner: Owner) {
        remove { $0.owner == owner }
    }

    /// Removes every file made from these history records (record deleted or expired).
    func release(records: some Sequence<UUID>) {
        let ids = Set(records)
        guard !ids.isEmpty else { return }
        remove { $0.record.map(ids.contains) ?? false }
    }

    /// Removes this launch's folder and everything in it (quit).
    func removeAll() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: launchFolder)
    }

    /// Removes what earlier launches left behind: loose files and folders in `root` from older
    /// builds, and `launch-<pid>` folders whose process is gone. Another running copy keeps its own.
    func purgeStale() {
        let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for child in children where child.standardizedFileURL != launchFolder.standardizedFileURL {
            let name = child.lastPathComponent
            if name.hasPrefix(Self.folderPrefix), let pid = Int32(name.dropFirst(Self.folderPrefix.count)),
               Self.isRunning(pid) { continue }
            try? FileManager.default.removeItem(at: child)
        }
    }

    /// Tracked paths, for tests.
    var trackedURLs: [URL] { entries.map(\.url) }

    private func remove(where matches: (Entry) -> Bool) {
        for entry in entries where matches(entry) {
            try? FileManager.default.removeItem(at: entry.url)
            // A file in its own folder from `makeFolder()`: drop the empty folder too.
            let parent = entry.url.deletingLastPathComponent()
            if parent.deletingLastPathComponent().standardizedFileURL == launchFolder.standardizedFileURL,
               (try? FileManager.default.contentsOfDirectory(atPath: parent.path))?.isEmpty == true {
                try? FileManager.default.removeItem(at: parent)
            }
        }
        entries.removeAll(where: matches)
    }

    private static func isRunning(_ pid: Int32) -> Bool {
        pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
    }
}

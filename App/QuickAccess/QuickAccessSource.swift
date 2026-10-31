import Foundation
import ImageIO
import ScreenCapKit

/// Turns a file or history record into a Quick Access result, for `add-quick-access-overlay`,
/// History → Restore, and Restore Recently Closed (#41). No UI, so it is unit-tested.
@MainActor
enum QuickAccessSource {
    /// The record with `recordID`, else the history record stored at `url`, else `url` itself.
    /// A file that isn't in history is added as a `.pinnedImport` record so close, restore and
    /// OCR work on it like on a capture. Nil when the image can't be read.
    static func result(url: URL?, recordID: UUID?, history: HistoryStore?) async -> CaptureResult? {
        let record = await findRecord(url: url, recordID: recordID, history: history)
        guard let fileURL = record?.fileURL ?? url, let image = loadImage(fileURL) else { return nil }
        if let record { return QuickAccessItem.result(from: record, image: image) }
        if let history, let added = try? await history.add(image: image, kind: .pinnedImport) {
            return QuickAccessItem.result(from: added, image: image)
        }
        return QuickAccessItem.result(image: image, scale: 1, kind: .area,
                                      context: FilenameTemplate.Context(), recordID: nil)
    }

    private static func findRecord(url: URL?, recordID: UUID?, history: HistoryStore?) async -> CaptureRecord? {
        guard let history else { return nil }
        if let recordID, let record = await history.record(id: recordID) { return record }
        guard let path = url?.standardizedFileURL.path else { return nil }
        return await history.records().first { $0.fileURL.standardizedFileURL.path == path }
    }

    static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

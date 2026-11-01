import AppKit
import ScreenCapKit

/// One capture on screen in Quick Access: its result, panel, timer and save state.
@MainActor
final class QuickAccessItem {
    let result: CaptureResult
    let panel: QuickAccessPanel
    var timer: AutoCloseTimer
    var savedURL: URL?
    var savedBytes: Int64?
    /// Temp file and PNG data for drag-out, prepared in the background after the panel appears.
    var drag = QuickAccessDragContents()
    var prepareTask: Task<Void, Never>?
    var isHovered = false
    /// The panel is key via Focus Quick Access (#129); its timer is paused meanwhile.
    var isFocused = false
    /// Where the stack layout put the panel; swipes move it relative to this.
    var baseFrame: CGRect = .zero
    /// Past the visible-panel cap: ordered out, timer paused, counted in the "+N" badge (#116).
    var isOverflowed = false
    /// Owns this panel's drag-out temp files; released when the panel goes (#114).
    let tempOwner = TempFiles.Owner.token(UUID())
    private var flashTask: Task<Void, Never>?

    init(result: CaptureResult, panel: QuickAccessPanel, timer: AutoCloseTimer) {
        self.result = result
        self.panel = panel
        self.timer = timer
    }

    // MARK: - Info line

    func refreshInfo() {
        let unsaved = result.historyWriteFailed ? "Not saved · not in History" : "Not saved"
        panel.setInfo(dimensions: dimensionsText, name: savedURL?.lastPathComponent ?? unsaved)
    }

    /// The capture exists only in this panel: History couldn't store it and it isn't saved (#113).
    /// Such a panel never auto-closes and asks before closing.
    var isOnlyCopy: Bool { result.historyWriteFailed && savedURL == nil }

    /// Shows a short status ("Copied") in place of the filename for a moment.
    func flash(_ message: String) {
        flashTask?.cancel()
        panel.setInfo(dimensions: dimensionsText, name: message)
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.refreshInfo()
        }
    }

    private var dimensionsText: String {
        let size = result.image.pixelSize
        let dimensions = "\(Int(size.width)) × \(Int(size.height)) px"
        guard let savedBytes else { return dimensions }
        return dimensions + " · " + ByteCountFormatter.string(fromByteCount: savedBytes, countStyle: .file)
    }

    // MARK: - Drag-out

    /// What a drag carries right now. Prefers the saved file; encodes PNG on the spot if the
    /// background preparation hasn't finished. Both honor the Retina 1x/2x output scale (#87).
    func dragContents(scale: RetinaScale) -> QuickAccessDragContents {
        var contents = drag
        if let savedURL { contents.fileURL = savedURL }
        if contents.pngData == nil {
            contents.pngData = Self.encode(result.image, scale: scale, format: .png)
        }
        return contents
    }

    /// The image at the output scale (same `OutputScaler` path as Save), encoded. Nil on failure
    /// rather than a full-size image.
    nonisolated static func encode(_ image: CapturedImage, scale: RetinaScale, format: ExportFormat) -> Data? {
        guard let scaled = try? OutputScaler.scaled(image, to: scale) else { return nil }
        return try? Exporter(image: scaled.cgImage, format: format, scale: Double(scaled.scale)).data()
    }

    /// Encodes PNG data and writes a temp file named by the filename template, in the save format
    /// and at the output scale, in a new folder under `root`. The panel and History keep the
    /// full-resolution capture. The caller tracks the folder in `TempFiles` (#114).
    static func prepareDrag(for result: CaptureResult, options: SaveOptions, in root: URL) async
        -> QuickAccessDragContents {
        let image = result.image
        let scale = options.scale
        let format = ExportFormat(options.format, quality: options.jpegQuality)
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent(options.template().filename(context: result.context))
        return await Task.detached(priority: .utility) {
            let png = encode(image, scale: scale, format: .png)
            let fileData = format == .png ? png : encode(image, scale: scale, format: format)
            guard let fileData,
                  (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil,
                  (try? fileData.write(to: url, options: .atomic)) != nil
            else { return QuickAccessDragContents(fileURL: nil, pngData: png) }
            return QuickAccessDragContents(fileURL: url, pngData: png)
        }.value
    }

    // MARK: - Restore from history

    /// Rebuilds a capture result from a history record (Restore, `add-quick-access-overlay`).
    static func result(from record: CaptureRecord, image: CGImage) -> CaptureResult {
        result(image: image, scale: CGFloat(max(record.scale, 1)),
               kind: CaptureKind(rawValue: record.kind.rawValue) ?? .area,
               context: FilenameTemplate.Context(app: record.appName, window: record.windowTitle),
               recordID: record.id)
    }

    static func result(image: CGImage, scale: CGFloat, kind: CaptureKind, context: FilenameTemplate.Context,
                       recordID: UUID?) -> CaptureResult {
        let points = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        var context = context
        context.kind = kind.filenameKind
        var result = CaptureResult(
            image: CapturedImage(cgImage: image, scale: scale, pointRect: CGRect(origin: .zero, size: points),
                                 displayID: nil),
            kind: kind, context: context
        )
        result.historyRecordID = recordID
        return result
    }
}

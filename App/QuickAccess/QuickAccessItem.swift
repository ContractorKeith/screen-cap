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
    /// Where the stack layout put the panel; swipes move it relative to this.
    var baseFrame: CGRect = .zero
    private var flashTask: Task<Void, Never>?

    init(result: CaptureResult, panel: QuickAccessPanel, timer: AutoCloseTimer) {
        self.result = result
        self.panel = panel
        self.timer = timer
    }

    // MARK: - Info line

    func refreshInfo() {
        panel.setInfo(dimensions: dimensionsText, name: savedURL?.lastPathComponent ?? "Not saved")
    }

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
    /// background preparation hasn't finished.
    func dragContents() -> QuickAccessDragContents {
        var contents = drag
        if let savedURL { contents.fileURL = savedURL }
        if contents.pngData == nil {
            contents.pngData = try? Exporter(image: result.image.cgImage, format: .png,
                                             scale: Double(result.image.scale)).data()
        }
        return contents
    }

    /// Folder for drag-out temp files; emptied when Quick Access starts.
    static let temporaryFolder = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScreenCap/QuickAccess", isDirectory: true)

    /// Encodes PNG data and writes a temp file named by the filename template, in the save format.
    static func prepareDrag(for result: CaptureResult, options: SaveOptions) async -> QuickAccessDragContents {
        let image = result.image
        let format = ExportFormat(options.format, quality: options.jpegQuality)
        let folder = temporaryFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent(options.template().filename(context: result.context))
        return await Task.detached(priority: .utility) {
            let png = try? Exporter(image: image.cgImage, format: .png, scale: Double(image.scale)).data()
            let fileData = format == .png
                ? png
                : try? Exporter(image: image.cgImage, format: format, scale: Double(image.scale)).data()
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

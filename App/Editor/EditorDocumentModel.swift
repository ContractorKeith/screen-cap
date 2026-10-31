import AppKit
import Foundation
import Observation
import ScreenCapKit
import UniformTypeIdentifiers

enum EditorError: LocalizedError {
    case unreadableImage(URL)
    case noImageOnClipboard
    case renderFailed

    var errorDescription: String? {
        switch self {
        case let .unreadableImage(url): "“\(url.lastPathComponent)” isn’t an image ScreenCap can open."
        case .noImageOnClipboard: "There’s no image on the clipboard."
        case .renderFailed: "The image couldn’t be rendered."
        }
    }
}

/// Everything one editor window edits: the document, its images, selection, current tool and
/// undo history. Every change goes through `perform`, so undo, dirty state and redraws stay in step.
@MainActor
@Observable
final class EditorDocumentModel {
    private(set) var history: UndoStack<EditorSnapshot>
    var selection: Set<UUID> = []
    var tool: EditorTool = .arrow {
        didSet { if tool != .crop { cropRect = nil } }
    }
    /// Style and per-kind options for new objects; the inspector edits these.
    var options = ToolOptions()
    /// Where ⌘S writes. Nil until the document is saved or opened as a `.screencap`.
    var fileURL: URL?
    private(set) var isDirty = false
    /// Bumped on every change; the canvas redraws on it.
    private(set) var revision = 0
    /// Text object being edited in place; hidden from the canvas render while editing.
    var editingTextID: UUID?

    // Crop mode state (image pixels).
    var cropRect: CGRect?
    var cropAspect: CropAspect = .free
    var customAspect = CGSize(width: 3, height: 2)
    var cropEdges = CropEdges()

    /// Filename tokens for Save to Desktop.
    var filenameContext = FilenameTemplate.Context()
    @ObservationIgnored let renderer = Renderer()
    /// Called after every change, for AppKit views that don't use Observation.
    @ObservationIgnored var onChange: (() -> Void)?

    init(snapshot: EditorSnapshot, fileURL: URL? = nil) {
        history = UndoStack(snapshot)
        self.fileURL = fileURL
    }

    var snapshot: EditorSnapshot { history.current }
    var document: Document { history.current.document }
    var baseImage: CGImage { history.current.baseImage }
    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    var selectedAnnotations: [Annotation] {
        document.annotations.filter { selection.contains($0.id) }
    }

    func selectionContains(_ matches: (Annotation.Kind) -> Bool) -> Bool {
        selectedAnnotations.contains { matches($0.kind) }
    }

    /// The single selected annotation, if exactly one is selected.
    var singleSelection: Annotation? {
        selection.count == 1 ? selection.first.flatMap(document.annotation(withID:)) : nil
    }

    // MARK: - Opening

    /// Opens a `.screencap` package or an image file (PNG, JPEG, HEIC, TIFF...).
    static func open(_ url: URL) throws -> EditorDocumentModel {
        if url.pathExtension.lowercased() == ProjectFile.fileExtension {
            let contents = try ProjectFile.read(from: url)
            var snapshot = EditorSnapshot(document: contents.document, baseImage: contents.baseImage,
                                          layers: contents.layers)
            snapshot.backgroundAspect = inferredAspect(contents.document)
            return EditorDocumentModel(snapshot: snapshot, fileURL: url)
        }
        guard let loaded = ImageOps.load(url) else { throw EditorError.unreadableImage(url) }
        let model = EditorDocumentModel(snapshot: EditorSnapshot(image: loaded.image, scale: loaded.scale))
        model.filenameContext = FilenameTemplate.Context(window: url.deletingPathExtension().lastPathComponent)
        return model
    }

    /// The canvas aspect ratio a saved document was set to, if its canvas is wider or taller
    /// than plain padding makes it.
    static func inferredAspect(_ document: Document) -> Double? {
        guard let background = document.background else { return nil }
        let padded = BackgroundMath.canvasSize(imageSize: document.baseImage.pixelSize, background: background,
                                               aspect: nil)
        let canvas = document.canvasSize
        guard canvas.height > 0, abs(canvas.width - padded.width) > 1 || abs(canvas.height - padded.height) > 1
        else { return nil }
        return canvas.width / canvas.height
    }

    // MARK: - Core edit path

    /// Applies `change` to a copy of the current state and records it as one undo step.
    /// Calls with the same non-nil `groupKey` in a row coalesce (a drag, a slider).
    func perform(groupKey: String? = nil, _ change: (inout EditorSnapshot) -> Void) {
        var next = history.current
        change(&next)
        history.record(next, groupKey: groupKey)
        didChange()
    }

    /// Edits the document only.
    func edit(groupKey: String? = nil, _ change: (inout Document) -> Void) {
        perform(groupKey: groupKey) { change(&$0.document) }
    }

    /// Closes an open coalescing group (end of a drag).
    func endGrouping() {
        history.endGrouping()
    }

    func undo() {
        guard history.undo() != nil else { return }
        didChange()
    }

    func redo() {
        guard history.redo() != nil else { return }
        didChange()
    }

    func markSaved(to url: URL) {
        fileURL = url
        isDirty = false
    }

    private func didChange() {
        let ids = Set(document.annotations.map(\.id))
        if !selection.isSubset(of: ids) { selection.formIntersection(ids) }
        if let editing = editingTextID, !ids.contains(editing) { editingTextID = nil }
        isDirty = true
        revision &+= 1
        onChange?()
    }

    /// Redraw without an undo step (selection or crop overlay changes).
    func touch() {
        revision &+= 1
        onChange?()
    }

    // MARK: - Rendering

    /// Layers the renderer needs: the document's plus a bundled background image.
    var renderLayers: [String: CGImage] {
        var layers = snapshot.layers
        if case let .bundled(name) = document.background?.fill, let image = BundledBackgrounds.image(named: name) {
            layers[name] = image
        }
        return layers
    }

    /// Flattened image of the document at `scale` output pixels per document pixel.
    func renderedImage(scale: Double = 1, hiding hidden: UUID? = nil) throws -> CGImage {
        var document = document
        if let hidden { document.annotations.removeAll { $0.id == hidden } }
        return try renderer.image(for: document, baseImage: baseImage, layers: renderLayers,
                                  options: RenderOptions(scale: scale))
    }

    // MARK: - Saving

    /// UserDefaults key: the user has confirmed, once, that saving bakes redactions.
    static let redactionBakeConfirmedKey = "EditorRedactionBakeConfirmed"

    /// True when this save would flatten blur or pixelate and the user hasn't confirmed it yet.
    func needsRedactionBakeConfirmation(defaults: UserDefaults = .standard) -> Bool {
        ProjectFile.containsRedactions(document) && !defaults.bool(forKey: Self.redactionBakeConfirmedKey)
    }

    /// Writes a `.screencap` package. Objects stay editable, except blur and pixelate (and anything
    /// beneath them), which `ProjectFile` bakes into `base.png` so the original pixels aren't saved.
    func saveProject(to url: URL) throws {
        let canvas = document.canvasSize
        let previewScale = min(1, Double(ProjectFile.previewMaxPixels) / max(canvas.width, canvas.height, 1))
        let preview = try? renderedImage(scale: previewScale)
        try ProjectFile.write(document, baseImage: baseImage, layers: snapshot.referencedLayers,
                              preview: preview, to: url)
        markSaved(to: url)
    }

    /// Encoded export of the flattened image.
    func exportData(format: ExportFormat, scale: Double = 1) throws -> Data {
        let image = try renderedImage(scale: scale)
        let pointScale = document.baseImage.scale * scale
        return try Exporter(image: image, format: format, scale: max(pointScale, 0.01)).data()
    }
}

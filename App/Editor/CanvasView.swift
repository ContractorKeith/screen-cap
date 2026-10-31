import AppKit
import ScreenCapKit

/// The editor canvas: draws the document through `Renderer` and handles every pointer and key
/// interaction. It is the document view of an `NSScrollView`, sized in canvas pixels, so the
/// scroll view's magnification is the zoom (1 = one image pixel per point) and pinch works for free.
final class CanvasView: NSView {
    let model: EditorDocumentModel
    var drag: DragState = .idle
    var textEditor: NSTextView?
    private var cachedRender: CGImage?
    private var cachedRevision = -1
    private var cachedHidden: UUID?

    /// What the current mouse drag is doing. Points are in image pixels.
    enum DragState {
        case idle
        case creating(start: CGPoint, id: UUID?, group: String)
        case freehand(points: [CGPoint], id: UUID?, group: String)
        case moving(start: CGPoint, applied: CGSize, group: String)
        case resizing(id: UUID, handle: Handle, original: Annotation.Kind, group: String)
        case rubberBand(start: CGPoint, current: CGPoint, base: Set<UUID>)
        case cropping(start: CGPoint)
        case cropResizing(handle: Handle, original: CGRect)
        case cropMoving(start: CGPoint, original: CGRect)
    }

    init(model: EditorDocumentModel) {
        self.model = model
        super.init(frame: CGRect(origin: .zero, size: model.document.canvasSize))
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Current zoom, from the enclosing scroll view.
    var magnification: Double { Double(enclosingScrollView?.magnification ?? 1) }

    /// Hit and handle tolerance in image pixels: a constant on-screen size at any zoom.
    var tolerance: Double { 6 / magnification }

    /// Where the base image (and annotation space) sits in the view.
    var imageFrame: CGRect { BackgroundMath.imageFrame(for: model.document) }

    /// View point → image pixel.
    func imagePoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x - imageFrame.minX, y: point.y - imageFrame.minY)
    }

    /// Image-pixel rect → view rect.
    func viewRect(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: imageFrame.minX, dy: imageFrame.minY)
    }

    /// Called by the model after every change.
    func modelDidChange() {
        let size = model.document.canvasSize
        if frame.size != size { setFrameSize(size) }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        drawCheckerboard(in: context)
        if let image = renderedImage() {
            context.saveGState()
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            context.interpolationQuality = magnification < 1 ? .high : .none
            context.draw(image, in: CGRect(origin: .zero, size: model.document.canvasSize))
            context.restoreGState()
        }
        context.saveGState()
        context.translateBy(x: imageFrame.minX, y: imageFrame.minY)
        if model.tool == .crop { drawCrop(in: context) } else { drawSelection(in: context) }
        if case let .rubberBand(start, current, _) = drag { drawRubberBand(start, current, in: context) }
        context.restoreGState()
    }

    /// The document render, re-made only when the model or the text being edited changes.
    private func renderedImage() -> CGImage? {
        if cachedRevision != model.revision || cachedHidden != model.editingTextID || cachedRender == nil {
            cachedRender = try? model.renderedImage(hiding: model.editingTextID)
            cachedRevision = model.revision
            cachedHidden = model.editingTextID
        }
        return cachedRender
    }

    private func drawCheckerboard(in context: CGContext) {
        let tile = 8 / magnification
        context.setFillColor(NSColor.white.cgColor)
        context.fill(bounds)
        context.setFillColor(NSColor(white: 0.88, alpha: 1).cgColor)
        guard tile > 0.5 else { return }
        var y = 0.0
        var row = 0
        while y < bounds.height {
            var x = (row % 2 == 0) ? 0 : tile
            while x < bounds.width {
                context.fill(CGRect(x: x, y: y, width: tile, height: tile))
                x += tile * 2
            }
            y += tile
            row += 1
        }
    }

    private func drawSelection(in context: CGContext) {
        let line = 1 / magnification
        let selected = model.selectedAnnotations
        for annotation in selected {
            let bounds = annotation.kind.bounds
            guard !bounds.isNull else { continue }
            switch annotation.kind {
            case .line, .arrow: break
            default:
                context.setStrokeColor(NSColor.controlAccentColor.cgColor)
                context.setLineWidth(line)
                context.setLineDash(phase: 0, lengths: [4 * line, 3 * line])
                context.stroke(bounds.insetBy(dx: -line, dy: -line))
                context.setLineDash(phase: 0, lengths: [])
            }
        }
        guard selected.count == 1, let only = selected.first else { return }
        if case let .arrow(start, end, .curved(control)) = only.kind {
            context.setStrokeColor(NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor)
            context.setLineWidth(line)
            context.strokeLineSegments(between: [start, control, control, end])
        }
        for (handle, point) in EditorGeometry.handles(for: only.kind) {
            drawHandle(at: point, round: handle == .control, in: context)
        }
    }

    func drawHandle(at point: CGPoint, round: Bool, in context: CGContext) {
        let radius = 4.5 / magnification
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        context.setFillColor(round ? NSColor.systemOrange.cgColor : NSColor.white.cgColor)
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(1.5 / magnification)
        context.fillEllipse(in: rect)
        context.strokeEllipse(in: rect)
    }

    private func drawRubberBand(_ start: CGPoint, _ current: CGPoint, in context: CGContext) {
        let rect = EditorGeometry.rect(from: start, to: current)
        context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor)
        context.fill(rect)
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(1 / magnification)
        context.stroke(rect)
    }

    private func drawCrop(in context: CGContext) {
        guard let crop = model.cropRect else { return }
        let image = CGRect(origin: .zero, size: model.snapshot.imageSize)
        let line = 1 / magnification
        context.saveGState()
        context.addRect(image)
        context.addRect(crop)
        context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        context.fillPath(using: .evenOdd)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(line)
        for third in [1.0 / 3, 2.0 / 3] {
            let x = crop.minX + crop.width * third, y = crop.minY + crop.height * third
            context.strokeLineSegments(between: [CGPoint(x: x, y: crop.minY), CGPoint(x: x, y: crop.maxY),
                                                 CGPoint(x: crop.minX, y: y), CGPoint(x: crop.maxX, y: y)])
        }
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2 * line)
        context.stroke(crop)
        context.restoreGState()
        for handle in Handle.boxHandles { drawHandle(at: handle.point(on: crop), round: false, in: context) }
    }

    override func resetCursorRects() {
        let cursor: NSCursor = switch model.tool {
        case .select: .arrow
        case .text: .iBeam
        default: .crosshair
        }
        addCursorRect(visibleRect, cursor: cursor)
    }
}

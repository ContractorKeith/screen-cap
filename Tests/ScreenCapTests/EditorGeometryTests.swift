import CoreGraphics
@testable import ScreenCap
import ScreenCapKit
import Testing

@Suite("Editor hit-testing and handles")
struct EditorGeometryTests {
    private func annotation(_ kind: Annotation.Kind, width: Double = 4, fill: RGBAColor? = nil) -> Annotation {
        Annotation(style: Annotation.Style(strokeWidth: width, fillColor: fill), kind: kind)
    }

    @Test func lineHitsNearSegmentOnly() {
        let line = annotation(.line(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0)))
        #expect(EditorGeometry.hits(line, at: CGPoint(x: 50, y: 5), tolerance: 4))
        #expect(!EditorGeometry.hits(line, at: CGPoint(x: 50, y: 12), tolerance: 4))
        #expect(!EditorGeometry.hits(line, at: CGPoint(x: 120, y: 0), tolerance: 4))
    }

    @Test func unfilledRectangleHitsOutlineFilledHitsInside() {
        let rect = CGRect(x: 10, y: 10, width: 100, height: 50)
        let outline = annotation(.rectangle(rect: rect, filled: false, cornerRadius: 0))
        #expect(EditorGeometry.hits(outline, at: CGPoint(x: 10, y: 30), tolerance: 3))
        #expect(!EditorGeometry.hits(outline, at: CGPoint(x: 60, y: 35), tolerance: 3))
        let filled = annotation(.rectangle(rect: rect, filled: true, cornerRadius: 0))
        #expect(EditorGeometry.hits(filled, at: CGPoint(x: 60, y: 35), tolerance: 3))
    }

    @Test func ellipseHitsRing() {
        let ellipse = annotation(.ellipse(rect: CGRect(x: 0, y: 0, width: 100, height: 100)))
        #expect(EditorGeometry.hits(ellipse, at: CGPoint(x: 100, y: 50), tolerance: 3))
        #expect(!EditorGeometry.hits(ellipse, at: CGPoint(x: 50, y: 50), tolerance: 3))
        let solid = annotation(.ellipse(rect: CGRect(x: 0, y: 0, width: 100, height: 100)), fill: .white)
        #expect(EditorGeometry.hits(solid, at: CGPoint(x: 50, y: 50), tolerance: 3))
    }

    @Test func curvedArrowHitsAlongCurveNotChord() {
        let start = CGPoint(x: 0, y: 0), end = CGPoint(x: 100, y: 0), control = CGPoint(x: 50, y: 100)
        let arrow = annotation(.arrow(start: start, end: end, style: .curved(control: control)))
        // The curve's midpoint is halfway to the control point.
        #expect(EditorGeometry.hits(arrow, at: CGPoint(x: 50, y: 50), tolerance: 3))
        #expect(!EditorGeometry.hits(arrow, at: CGPoint(x: 50, y: 0), tolerance: 3))
    }

    @Test func counterTextAndPathHits() {
        let counter = annotation(.counter(number: 1, center: CGPoint(x: 50, y: 50), radius: 10))
        #expect(EditorGeometry.hits(counter, at: CGPoint(x: 57, y: 50), tolerance: 0))
        #expect(!EditorGeometry.hits(counter, at: CGPoint(x: 70, y: 50), tolerance: 2))
        let box = CGRect(x: 0, y: 0, width: 80, height: 30)
        let text = annotation(.text(string: "Hi", preset: 1, fontSize: 20, rect: box))
        #expect(EditorGeometry.hits(text, at: CGPoint(x: 40, y: 15), tolerance: 0))
        let path = annotation(.path(points: [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50)], smoothed: false))
        #expect(EditorGeometry.hits(path, at: CGPoint(x: 26, y: 24), tolerance: 2))
    }

    @Test func topmostFollowsDrawOrder() {
        var document = Document(baseImage: Document.BaseImage(pixelWidth: 200, pixelHeight: 200, scale: 1))
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let bottom = document.add(annotation(.rectangle(rect: rect, filled: true, cornerRadius: 0)))
        let top = document.add(annotation(.rectangle(rect: rect, filled: true, cornerRadius: 0)))
        #expect(EditorGeometry.topmost(in: document, at: CGPoint(x: 50, y: 50), tolerance: 2) == top)
        document.sendToBack(top)
        #expect(EditorGeometry.topmost(in: document, at: CGPoint(x: 50, y: 50), tolerance: 2) == bottom)
        #expect(EditorGeometry.topmost(in: document, at: CGPoint(x: 150, y: 150), tolerance: 2) == nil)
    }

    @Test func handlesForBoxesAndLines() {
        let box = EditorGeometry.handles(for: .ellipse(rect: CGRect(x: 0, y: 0, width: 100, height: 50)))
        #expect(box.count == 8)
        #expect(box.first { $0.handle == .bottomRight }?.point == CGPoint(x: 100, y: 50))
        #expect(box.first { $0.handle == .top }?.point == CGPoint(x: 50, y: 0))
        let curved = Annotation.Kind.arrow(start: .zero, end: CGPoint(x: 10, y: 0),
                                           style: .curved(control: CGPoint(x: 5, y: 5)))
        #expect(EditorGeometry.handles(for: curved).map(\.handle) == [.start, .end, .control])
        #expect(EditorGeometry.handle(at: CGPoint(x: 6, y: 5), for: curved, tolerance: 2) == .control)
        #expect(EditorGeometry.handle(at: CGPoint(x: 50, y: 50), for: curved, tolerance: 2) == nil)
    }

    @Test func resizeByHandles() {
        let original = CGRect(x: 0, y: 0, width: 100, height: 50)
        #expect(EditorGeometry.resized(original, handle: .bottomRight, to: CGPoint(x: 200, y: 80), constrain: false)
            == CGRect(x: 0, y: 0, width: 200, height: 80))
        #expect(EditorGeometry.resized(original, handle: .left, to: CGPoint(x: 20, y: 999), constrain: false)
            == CGRect(x: 20, y: 0, width: 80, height: 50))
        // Dragging past the opposite edge flips instead of going negative.
        #expect(EditorGeometry.resized(original, handle: .right, to: CGPoint(x: -20, y: 0), constrain: false)
            == CGRect(x: -20, y: 0, width: 20, height: 50))
    }

    @Test func shiftKeepsAspectFromOppositeCorner() {
        let original = CGRect(x: 0, y: 0, width: 100, height: 50)
        let bigger = EditorGeometry.resized(original, handle: .bottomRight, to: CGPoint(x: 300, y: 60), constrain: true)
        #expect(bigger == CGRect(x: 0, y: 0, width: 300, height: 150))
        let topLeft = EditorGeometry.resized(original, handle: .topLeft, to: CGPoint(x: 50, y: 40), constrain: true)
        #expect(topLeft.maxX == 100 && topLeft.maxY == 50)
        #expect(abs(topLeft.width / topLeft.height - 2) < 0.0001)
    }

    @Test func endpointHandlesMoveAndSnap() {
        let line = Annotation.Kind.line(start: .zero, end: CGPoint(x: 100, y: 0))
        let moved = EditorGeometry.movingPoint(line, handle: .end, to: CGPoint(x: 70, y: 66), constrain: true)
        guard case let .line(start, end) = moved else { Issue.record("not a line"); return }
        #expect(start == .zero)
        #expect(abs(end.x - end.y) < 0.0001) // snapped to 45°
        let arrow = Annotation.Kind.arrow(start: .zero, end: CGPoint(x: 10, y: 0), style: .curved(control: .zero))
        let bent = EditorGeometry.movingPoint(arrow, handle: .control, to: CGPoint(x: 5, y: 30), constrain: false)
        #expect(bent == .arrow(start: .zero, end: CGPoint(x: 10, y: 0), style: .curved(control: CGPoint(x: 5, y: 30))))
    }
}

@Suite("Tool drags make annotation geometry")
struct ToolDragTests {
    let options = ToolOptions()

    @Test func rectangleFromAnyDragDirection() {
        let kind = ToolDrag.kind(for: .rectangle, from: CGPoint(x: 50, y: 60), to: CGPoint(x: 10, y: 20),
                                 constrain: false, options: options)
        #expect(kind == .rectangle(rect: CGRect(x: 10, y: 20, width: 40, height: 40), filled: false, cornerRadius: 0))
        let filled = ToolDrag.kind(for: .filledRectangle, from: .zero, to: CGPoint(x: 30, y: 10), constrain: true,
                                   options: options)
        #expect(filled == .rectangle(rect: CGRect(x: 0, y: 0, width: 30, height: 30), filled: true, cornerRadius: 0))
    }

    @Test func tinyDragsMakeNothingButClickToolsDo() {
        #expect(ToolDrag.kind(for: .ellipse, from: .zero, to: CGPoint(x: 1, y: 1), constrain: false,
                              options: options) == nil)
        let counter = ToolDrag.kind(for: .counter, from: .zero, to: CGPoint(x: 5, y: 6), constrain: false,
                                    options: options, nextCounter: 3)
        #expect(counter == .counter(number: 3, center: CGPoint(x: 5, y: 6), radius: options.counterRadius))
        guard case let .text(string, _, _, rect)? = ToolDrag.kind(for: .text, from: CGPoint(x: 10, y: 10),
                                                                   to: CGPoint(x: 10, y: 10), constrain: false,
                                                                   options: options)
        else { Issue.record("expected text"); return }
        #expect(string.isEmpty && rect.width > 0 && rect.height > 0)
    }

    @Test func arrowStylesAndAngleSnap() {
        var curvedOptions = options
        curvedOptions.arrow = .curved
        let curved = ToolDrag.kind(for: .arrow, from: .zero, to: CGPoint(x: 100, y: 0), constrain: false,
                                   options: curvedOptions)
        guard case let .arrow(_, _, .curved(control))? = curved else { Issue.record("expected curved"); return }
        #expect(control.x == 50 && control.y != 0)
        let snapped = ToolDrag.kind(for: .line, from: .zero, to: CGPoint(x: 100, y: 8), constrain: true,
                                    options: options)
        guard case let .line(_, end)? = snapped else { Issue.record("expected line"); return }
        #expect(abs(end.y) < 0.0001)
    }

    @Test func redactionAndSpotlightCarryTheirOptions() {
        var custom = options
        custom.blurMode = .smooth
        custom.blurRadius = 20
        custom.pixelateBlockSize = 9
        custom.spotlightShape = .ellipse
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        let end = CGPoint(x: 10, y: 10)
        #expect(ToolDrag.kind(for: .blur, from: .zero, to: end, constrain: false, options: custom)
            == .blur(rect: rect, mode: .smooth, radius: 20))
        #expect(ToolDrag.kind(for: .pixelate, from: .zero, to: end, constrain: false, options: custom)
            == .pixelate(rect: rect, blockSize: 9, randomize: true))
        #expect(ToolDrag.kind(for: .spotlight, from: .zero, to: end, constrain: false, options: custom)
            == .spotlight(shapes: [.ellipse(rect: rect)]))
    }

    @Test func freehandPencilAndHighlighter() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0), CGPoint(x: 5, y: 0), CGPoint(x: 10, y: 0)]
        #expect(ToolDrag.freehand(.pencil, points: points, options: options)
            == .path(points: [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 0), CGPoint(x: 10, y: 0)], smoothed: true))
        guard case .highlight(.path, _)? = ToolDrag.freehand(.highlighter, points: points, options: options)
        else { Issue.record("expected highlight"); return }
        #expect(ToolDrag.freehand(.highlighter, points: [.zero], options: options) == nil)
    }
}

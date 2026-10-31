import CoreGraphics
import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

@Suite("Crop snapping and zoom math")
struct CropAndZoomTests {
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)

    @Test func freeCropSnapsToImageAndDetectedEdges() {
        let edges = CropEdges(xEdges: [120], yEdges: [80])
        let rect = CropMath.rect(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 395, y: 84), ratio: nil, bounds: bounds,
                                 edges: edges, threshold: 8)
        #expect(rect == CGRect(x: 20, y: 20, width: 380, height: 60))
        let unsnapped = CropMath.rect(from: .zero, to: CGPoint(x: 200, y: 150), ratio: nil, bounds: bounds,
                                      edges: edges, threshold: 8)
        #expect(unsnapped == CGRect(x: 0, y: 0, width: 200, height: 150))
    }

    @Test func aspectCropKeepsRatioAndStaysInside() {
        let square = CropMath.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 110, y: 50), ratio: 1,
                                   bounds: bounds)
        #expect(square == CGRect(x: 10, y: 10, width: 100, height: 100))
        let wide = CropMath.rect(from: .zero, to: CGPoint(x: 160, y: 10), ratio: 16.0 / 9.0,
                                 bounds: bounds)
        #expect(wide == CGRect(x: 0, y: 0, width: 160, height: 90))
        let clamped = CropMath.rect(from: CGPoint(x: 350, y: 250), to: CGPoint(x: 500, y: 260), ratio: 1,
                                    bounds: bounds)
        #expect(bounds.contains(clamped))
    }

    @Test func snappedMovesEachEdgeIndependently() {
        let snapped = CropMath.snapped(CGRect(x: 5, y: 82, width: 110, height: 213), to: CropEdges(xEdges: [118]),
                                       bounds: bounds, threshold: 6)
        #expect(snapped == CGRect(x: 0, y: 82, width: 118, height: 218))
    }

    @Test func aspectPresets() {
        #expect(CropAspect.free.ratio(custom: .zero) == nil)
        #expect(CropAspect.fourThree.ratio(custom: .zero) == 4.0 / 3.0)
        #expect(CropAspect.custom.ratio(custom: CGSize(width: 3, height: 2)) == 1.5)
        #expect(CropAspect.custom.ratio(custom: CGSize(width: 3, height: 0)) == nil)
    }

    @Test func zoomToFit() {
        // A 2000×1000 canvas in a 1040×540 viewport with 20 pt margins fits at 0.5.
        #expect(ZoomMath.fit(content: CGSize(width: 2000, height: 1000), in: CGSize(width: 1040, height: 540)) == 0.5)
        // Small images aren't blown up past the cap.
        #expect(ZoomMath.fit(content: CGSize(width: 100, height: 100), in: CGSize(width: 1000, height: 1000)) == 1)
        #expect(ZoomMath.fit(content: CGSize(width: 100, height: 100), in: CGSize(width: 1000, height: 1000),
                             maxScale: 0.5) == 0.5)
        // Huge content is clamped to the minimum zoom.
        #expect(ZoomMath.fit(content: CGSize(width: 1_000_000, height: 10), in: CGSize(width: 500, height: 500))
            == ZoomMath.minimum)
    }

    @Test func zoomSteps() {
        #expect(ZoomMath.zoomIn(from: 1) == 1.5)
        #expect(ZoomMath.zoomOut(from: 1) == 0.75)
        #expect(ZoomMath.zoomIn(from: 0.6) == 0.667)
        #expect(ZoomMath.zoomIn(from: ZoomMath.maximum) == ZoomMath.maximum)
        #expect(ZoomMath.zoomOut(from: ZoomMath.minimum) == ZoomMath.minimum)
    }

    @Test func autoBalanceMapsToPaddingAndAlignment() {
        let shadowed = BackgroundMath.balanced(EffectsInsets(top: 40, left: 60, bottom: 80, right: 60))
        #expect(shadowed.padding == 40 && shadowed.alignment == .top)
        let even = BackgroundMath.balanced(EffectsInsets(all: 50))
        #expect(even.padding == 50 && even.alignment == .center)
    }
}

@Suite("Editor document model")
@MainActor
struct EditorModelTests {
    static func image(width: Int = 64, height: Int = 48) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func makeModel() -> EditorDocumentModel {
        EditorDocumentModel(snapshot: EditorSnapshot(image: Self.image(), scale: 2))
    }

    @Test func editUndoRedoSaveAndReopen() throws {
        let model = makeModel()
        let arrow = model.add(.arrow(start: CGPoint(x: 2, y: 2), end: CGPoint(x: 40, y: 30),
                                     style: .curved(control: CGPoint(x: 30, y: 4))))
        model.add(.text(string: "Hello", preset: TextPreset.outlined.rawValue, fontSize: 14,
                        rect: CGRect(x: 4, y: 4, width: 50, height: 20)))
        model.add(.counter(number: 1, center: CGPoint(x: 10, y: 40), radius: 6))
        model.selection = [arrow]
        model.moveSelection(by: CGSize(width: 3, height: 1), groupKey: "drag")
        model.moveSelection(by: CGSize(width: 2, height: 0), groupKey: "drag")
        model.endGrouping()
        #expect(model.document.annotations.count == 3)
        #expect(model.isDirty)

        // The two moves coalesced into one undo step.
        model.undo()
        #expect(model.document.annotation(withID: arrow)?.kind.bounds.minX == 2)
        model.redo()
        #expect(model.document.annotation(withID: arrow)?.kind.bounds.minX == 7)
        model.undo()
        model.undo()
        #expect(model.document.annotations.count == 2)
        model.redo()
        model.redo()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-\(UUID().uuidString).\(ProjectFile.fileExtension)")
        defer { try? FileManager.default.removeItem(at: url) }
        try model.saveProject(to: url)
        #expect(!model.isDirty)

        let reopened = try EditorDocumentModel.open(url)
        #expect(reopened.document.annotations == model.document.annotations)
        #expect(reopened.document.baseImage == model.document.baseImage)
        #expect(reopened.fileURL == url)
    }

    @Test func imageLayersAndBackgroundSurviveSave() throws {
        let model = makeModel()
        let layer = model.addImageLayer(Self.image(width: 10, height: 10), center: CGPoint(x: 20, y: 20))
        model.setBackground(Document.Background(fill: .bundled(name: BundledBackgrounds.names[3]), padding: 16),
                            aspect: 1)
        #expect(model.document.canvasSize.width == model.document.canvasSize.height)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-\(UUID().uuidString).\(ProjectFile.fileExtension)")
        defer { try? FileManager.default.removeItem(at: url) }
        try model.saveProject(to: url)
        let reopened = try EditorDocumentModel.open(url)
        #expect(reopened.document == model.document)
        #expect(reopened.snapshot.backgroundAspect == 1)
        guard case let .imageLayer(name, _)? = reopened.document.annotation(withID: layer)?.kind else {
            Issue.record("image layer missing")
            return
        }
        #expect(reopened.snapshot.layers[name] != nil)
        let render = try reopened.renderedImage()
        #expect(render.width == Int(model.document.canvasSize.width))
    }

    @Test func cropRotateAndFlipCarryAnnotations() {
        let model = makeModel()
        let id = model.add(.rectangle(rect: CGRect(x: 10, y: 10, width: 20, height: 10), filled: false,
                                      cornerRadius: 0))
        model.cropRect = CGRect(x: 5, y: 5, width: 40, height: 30)
        model.applyCrop()
        #expect(model.snapshot.imageSize == CGSize(width: 40, height: 30))
        #expect(model.document.annotation(withID: id)?.kind.bounds == CGRect(x: 5, y: 5, width: 20, height: 10))

        model.rotate(clockwise: true)
        #expect(model.snapshot.imageSize == CGSize(width: 30, height: 40))
        // Clockwise: (x, y) -> (H - y, x) with H = 30.
        #expect(model.document.annotation(withID: id)?.kind.bounds == CGRect(x: 15, y: 5, width: 10, height: 20))

        model.flip(horizontal: true)
        #expect(model.document.annotation(withID: id)?.kind.bounds == CGRect(x: 5, y: 5, width: 10, height: 20))

        model.undo()
        model.undo()
        model.undo()
        #expect(model.snapshot.imageSize == CGSize(width: 64, height: 48))
    }

    @Test func copyPasteDuplicateAndZOrder() throws {
        let model = makeModel()
        let first = model.add(.counter(number: 1, center: CGPoint(x: 10, y: 10), radius: 5))
        let second = model.add(.ellipse(rect: CGRect(x: 0, y: 0, width: 20, height: 20)))
        model.selection = [first]
        let payload = try #require(model.clipboardPayload())
        let decoded = try JSONDecoder().decode(AnnotationClipboard.self, from: JSONEncoder().encode(payload))
        model.paste(decoded)
        let pasted = try #require(model.selection.first)
        #expect(pasted != first)
        guard case let .counter(number, center, _)? = model.document.annotation(withID: pasted)?.kind else {
            Issue.record("expected counter")
            return
        }
        #expect(number == 2 && center == CGPoint(x: 26, y: 26))

        model.selection = [second]
        model.duplicateSelection()
        #expect(model.document.annotations.count == 4)

        model.selection = [first]
        model.arrange(.front)
        #expect(model.document.drawOrder.last?.id == first)
        model.arrange(.back)
        #expect(model.document.drawOrder.first?.id == first)

        model.selection = [first]
        model.deleteSelection()
        // Remaining counter renumbers to 1.
        #expect(model.document.nextCounterNumber == 2)
    }
}

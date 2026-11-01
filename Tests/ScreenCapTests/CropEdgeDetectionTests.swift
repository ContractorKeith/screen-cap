import AppKit
@testable import ScreenCap
import ScreenCapKit
import Testing

@Suite("Crop edge detection")
@MainActor
struct CropEdgeDetectionTests {
    private func makeModel() throws -> EditorDocumentModel {
        let context = try #require(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                            bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 50, y: 0, width: 50, height: 100))
        let image = try #require(context.makeImage())
        return EditorDocumentModel(snapshot: EditorSnapshot(image: image, scale: 1))
    }

    @Test func beginCropPublishesDetectedEdges() async throws {
        let model = try makeModel()
        await model.beginCrop().value
        #expect(model.cropEdges.xEdges == [50])
    }

    @Test func editDuringDetectionDiscardsStaleEdges() async throws {
        let model = try makeModel()
        #expect(CropEdgeDetector.edges(in: model.baseImage).xEdges == [50])
        let detection = model.beginCrop()
        let revision = model.revision
        // Stay on the main actor until the edit, so detection cannot publish first.
        model.flip(horizontal: true)
        #expect(model.revision > revision)
        await detection.value
        #expect(model.cropEdges.xEdges.isEmpty)
        #expect(model.cropEdges.yEdges.isEmpty)
    }

    @Test func canvasCropDragsUseDetectedEdges() async throws {
        let model = try makeModel()
        await model.beginCrop().value
        let canvas = CanvasView(model: model)
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDragged, location: CGPoint(x: 54, y: 75),
                                                  modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                  context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        canvas.drag = .cropping(start: CGPoint(x: 20, y: 20))
        canvas.mouseDragged(with: event)
        #expect(model.cropRect?.maxX == 50)

        canvas.drag = .cropResizing(handle: .bottomRight, original: CGRect(x: 20, y: 20, width: 50, height: 50))
        canvas.mouseDragged(with: event)
        #expect(model.cropRect?.maxX == 50)
    }
}

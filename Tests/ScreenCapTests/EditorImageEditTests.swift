import CoreGraphics
import Foundation
import ImageIO
@testable import ScreenCap
import ScreenCapKit
import Testing

/// Base-image edits and the background canvas: #54 (Auto Balance insets), #55 (resize scale),
/// #56 (counter side handles) and #63 (undo memory).
@Suite("Editor image edits")
@MainActor
struct EditorImageEditTests {
    private func makeModel(width: Int = 64, height: Int = 48, scale: Double = 2) -> EditorDocumentModel {
        EditorDocumentModel(snapshot: EditorSnapshot(image: EditorModelTests.image(width: width, height: height),
                                                     scale: scale))
    }

    // MARK: #54

    @Test func autoBalanceInsetsSurviveOtherBackgroundEdits() throws {
        let model = makeModel()
        let insets = EffectsInsets(top: 20, left: 30, bottom: 60, right: 30)
        model.setBackground(Document.Background(fill: .solid(color: .white), padding: 20, alignment: .top,
                                                edgePadding: insets), aspect: nil)
        let balanced = CGSize(width: 64 + 60, height: 48 + 80)
        #expect(model.document.canvasSize == balanced)

        model.updateBackground(groupKey: "bg-radius") { $0.cornerRadius = 13 }
        model.updateBackground { $0.shadow = nil }
        model.updateBackground { $0.shadow = Document.Shadow() }
        model.updateBackground { $0.fill = .solid(color: .black) }
        #expect(model.document.canvasSize == balanced)
        #expect(model.document.background?.edgePadding == insets)

        model.cropRect = CGRect(x: 0, y: 0, width: 40, height: 30)
        model.applyCrop()
        #expect(model.document.canvasSize == CGSize(width: 40 + 60, height: 30 + 80))

        // Changing padding explicitly goes back to uniform padding.
        model.updateBackground(groupKey: "bg-padding") { $0.padding = 10 }
        #expect(model.document.background?.edgePadding == nil)
        #expect(model.document.canvasSize == CGSize(width: 40 + 20, height: 30 + 20))
    }

    @Test func autoBalanceStoresEdgesThatFitTheRendererPlacement() {
        let fit = BackgroundMath.balanced(EffectsInsets(top: 20, left: 10, bottom: 60, right: 10))
        #expect(fit.padding == 20 && fit.alignment == .top)
        // Horizontal edges are raised to the padding so the image never overflows the canvas.
        #expect(fit.edges == EffectsInsets(top: 20, left: 20, bottom: 60, right: 20))

        let model = makeModel()
        model.autoBalance()
        let background = model.document.background
        let edges = background?.edgePadding
        #expect(edges != nil)
        if let edges {
            #expect(model.document.canvasSize == CGSize(width: 64 + edges.left + edges.right,
                                                        height: 48 + edges.top + edges.bottom))
        }
        let frame = BackgroundMath.imageFrame(for: model.document)
        #expect(CGRect(origin: .zero, size: model.document.canvasSize).contains(frame))
    }

    // MARK: #55

    @Test func resizeUpdatesScaleAndExportDPI() throws {
        let model = makeModel(width: 2000, height: 1000, scale: 2)
        let id = model.add(.blur(rect: CGRect(x: 0, y: 0, width: 100, height: 100), mode: .secure, radius: 20))
        model.resizeImage(to: CGSize(width: 1000, height: 500))
        #expect(model.document.baseImage.scale == 1)
        #expect(model.document.annotation(withID: id)?.style.strokeWidth == 2)
        if case let .blur(_, _, radius)? = model.document.annotation(withID: id)?.kind {
            #expect(radius == 10)
        } else {
            Issue.record("blur missing")
        }

        let data = try model.exportData(format: .png)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyDPIWidth] as? Double == 72)
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 1000)

        // Crop, rotate and flip keep the scale.
        model.rotate(clockwise: true)
        model.cropRect = CGRect(x: 0, y: 0, width: 100, height: 100)
        model.applyCrop()
        #expect(model.document.baseImage.scale == 1)
        model.undo()
        model.undo()
        model.undo()
        #expect(model.document.baseImage.scale == 2)
    }

    // MARK: #56

    @Test func counterSideHandlesResize() throws {
        let model = makeModel(width: 400, height: 400)
        let original = Annotation.Kind.counter(number: 1, center: CGPoint(x: 200, y: 200), radius: 18)
        let id = model.add(original)
        for handle in Handle.boxHandles {
            let start = handle.point(on: original.bounds)
            func away(_ value: Double) -> Double { value == 200 ? 0 : (value < 200 ? -40 : 40) }
            let dx = away(start.x), dy = away(start.y)
            let outward = CGPoint(x: start.x + dx, y: start.y + dy)
            var bounds = EditorGeometry.resized(original.bounds, handle: handle, to: outward, constrain: false)
            bounds.size = CGSize(width: max(bounds.width, 1), height: max(bounds.height, 1))
            var restored = model.document
            let index = try #require(restored.index(of: id))
            restored.annotations[index].kind = original
            restored.resize(id, to: bounds)
            guard case let .counter(_, _, radius) = restored.annotations[index].kind else { continue }
            #expect(radius > 18, "\(handle) left the counter at radius \(radius)")
            // The dragged handle ends up under the pointer.
            let moved = handle.point(on: restored.annotations[index].kind.bounds)
            #expect(abs(moved.x - outward.x) < 1e-9 && abs(moved.y - outward.y) < 1e-9, "\(handle): \(moved)")
        }
    }

    // MARK: #63

    @Test func fiftyCropsKeepOnlyAFewBitmaps() {
        let model = makeModel(width: 200, height: 200)
        model.add(.rectangle(rect: CGRect(x: 120, y: 120, width: 10, height: 10), filled: false, cornerRadius: 0))
        for step in 0..<50 {
            model.cropRect = CGRect(x: 0, y: 0, width: 199 - step, height: 199 - step)
            model.applyCrop()
        }
        #expect(model.snapshot.imageSize == CGSize(width: 150, height: 150))
        let bitmaps = Set(model.history.allStates.map { ObjectIdentifier($0.baseImage) })
        #expect(bitmaps.count <= EditorDocumentModel.maxUndoBitmaps)
        #expect(model.history.undoCount == EditorDocumentModel.maxUndoBitmaps - 1)
        // The most recent crops still undo.
        model.undo()
        #expect(model.snapshot.imageSize == CGSize(width: 151, height: 151))
    }
}

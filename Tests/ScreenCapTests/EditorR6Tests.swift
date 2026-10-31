import AppKit
import CoreGraphics
import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

/// #110 (resize limits), #111 (closed editors are released), #118 (no checkerboard past the canvas).
@Suite("Editor resize limits, window release, checkerboard")
@MainActor
struct EditorR6Tests {
    private let posix = Locale(identifier: "en_US_POSIX")

    // MARK: #110

    @Test func resizeRejectsTheIssueInputs() {
        // The repro: 1 000 000 wide with aspect kept (222 219 high), and an extra zero on 2940 × 1912.
        #expect(ResizeLimits.validate(width: 1_000_000, height: 222_219).size == nil)
        #expect(ResizeLimits.validate(width: 29_400, height: 19_120).size == nil)
        // Over the total budget though each side is legal: 16 000 × 16 000 = 256 MP.
        #expect(ResizeLimits.validate(width: 16_000, height: 16_000).message?.contains("megapixels") == true)
        // Non-finite, empty, zero and negative.
        #expect(ResizeLimits.validate(width: .infinity, height: 100).size == nil)
        #expect(ResizeLimits.validate(width: .nan, height: 100).size == nil)
        #expect(ResizeLimits.validate(width: nil, height: 100).size == nil)
        #expect(ResizeLimits.validate(width: 0, height: 100).size == nil)
        #expect(ResizeLimits.validate(width: -5, height: 100).size == nil)
        #expect(ResizeLimits.validate(width: 16_385, height: 1).size == nil)
    }

    @Test func resizeAcceptsSaneSizes() {
        #expect(ResizeLimits.validate(width: 2940, height: 1912).size == CGSize(width: 2940, height: 1912))
        #expect(ResizeLimits.validate(width: 1, height: 1).size == CGSize(width: 1, height: 1))
        #expect(ResizeLimits.validate(width: 16_384, height: 3_900).size != nil)
        #expect(ResizeLimits.validate(width: 8000, height: 8000).size != nil)   // exactly 64 MP
        #expect(ResizeLimits.validate(width: 1470.4, height: 956.6).size == CGSize(width: 1470, height: 957))
    }

    @Test func parseRejectsNonNumbersAndNonFinite() {
        #expect(ResizeLimits.parse("2940", locale: posix) == 2940)
        #expect(ResizeLimits.parse("2,940", locale: Locale(identifier: "en_US")) == 2940)
        #expect(ResizeLimits.parse(" 222219 ", locale: posix) == 222_219)
        for text in ["", "  ", "abc", "inf", "nan", "infinity", "1e400"] {
            #expect(ResizeLimits.parse(text, locale: posix) == nil, "\(text)")
        }
        #expect(ResizeLimits.text(.infinity) == "")
        #expect(ResizeLimits.text(222_218.6) == "222219")
    }

    @Test func modelIgnoresOversizedResize() {
        let model = EditorDocumentModel(snapshot: EditorSnapshot(image: EditorModelTests.image(width: 64, height: 48),
                                                                 scale: 1))
        model.resizeImage(to: CGSize(width: 1_000_000, height: 750_000))
        #expect(model.snapshot.imageSize == CGSize(width: 64, height: 48))
        #expect(!model.canUndo)
        #expect(ImageOps.resize(model.baseImage, to: CGSize(width: 40_000, height: 10)) == nil)
        model.resizeImage(to: CGSize(width: 128, height: 96))
        #expect(model.snapshot.imageSize == CGSize(width: 128, height: 96))
    }

    // MARK: #111

    @Test func closedEditorWindowIsReleased() {
        weak var weakController: EditorWindowController?
        weak var weakModel: EditorDocumentModel?
        weak var weakWindow: NSWindow?
        weak var weakCanvas: CanvasView?
        var closed = false
        autoreleasepool {
            let image = EditorModelTests.image(width: 64, height: 48)
            let model = EditorDocumentModel(snapshot: EditorSnapshot(image: image, scale: 1))
            let settings = AppSettings(store: InMemorySettingsStore())
            let controller = EditorWindowController(model: model, settings: settings,
                                                    preferences: EditorPreferences(store: InMemorySettingsStore()))
            controller.onClose = { _ in closed = true }
            controller.window?.orderFront(nil)
            controller.window?.contentView?.layoutSubtreeIfNeeded()
            weakController = controller
            weakModel = model
            weakWindow = controller.window
            weakCanvas = controller.canvas
            controller.window?.performClose(nil)
        }
        #expect(closed)
        // Let the run loop drain autoreleased AppKit and SwiftUI objects.
        let deadline = Date().addingTimeInterval(3)
        while weakModel != nil || weakController != nil || weakWindow != nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        #expect(weakController == nil)
        #expect(weakModel == nil)
        #expect(weakCanvas == nil)
        #expect(weakWindow == nil)
    }

    // MARK: #118

    @Test(arguments: [1.0, 0.5, 0.37, 0.123, 1.0 / 3, 2.6, 0.0625])
    func checkerboardStaysInsideTheCanvas(zoom: Double) {
        let bounds = CGRect(x: 0, y: 0, width: 1800, height: 401)
        let tile = 8 / zoom
        let tiles = CanvasView.checkerTiles(in: bounds, tile: tile, dirty: bounds)
        #expect(!tiles.isEmpty)
        for rect in tiles {
            #expect(bounds.contains(rect), "tile \(rect) spills past \(bounds) at zoom \(zoom)")
        }
        // The squares reach the right and bottom edges exactly, no further.
        let maxX = tiles.map(\.maxX).max() ?? 0, maxY = tiles.map(\.maxY).max() ?? 0
        #expect(abs(maxX - bounds.maxX) < 1e-9)
        #expect(abs(maxY - bounds.maxY) < 1e-9)
    }

    @Test func checkerboardDirtyRectMatchesFullPattern() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        let tile = 8 / 0.37
        let dirty = CGRect(x: 101.5, y: 40.2, width: 77, height: 90)
        let full = Set(CanvasView.checkerTiles(in: bounds, tile: tile, dirty: bounds)
            .filter { $0.intersects(dirty) }.map { "\($0)" })
        let partial = Set(CanvasView.checkerTiles(in: bounds, tile: tile, dirty: dirty).map { "\($0)" })
        #expect(partial == full)
    }
}

import CoreGraphics
import Foundation
@testable import ScreenCapKit
import Testing

@Suite("Renderer numeric validation")
struct RendererValidationTests {
    @Test(arguments: [1e100, Double.nan, .infinity, -.infinity, -1, 0])
    func invalidCanvasDoesNotTrap(value: Double) {
        let document = Document(baseImage: .init(pixelWidth: 20, pixelHeight: 20, scale: 2),
                                canvasSize: CGSize(width: value, height: 20),
                                background: .init(fill: .solid(color: .white)))
        let size = Renderer.pixelSize(for: document, options: RenderOptions())
        #expect(size.width == 0 && size.height == 0)
        #expect(throws: ProjectFileError.invalidGeometry("canvas size")) {
            try Renderer().image(for: document, baseImage: RenderFixtures.solidImage(.white))
        }
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -1, 0, 1e100, 1e-100])
    func invalidRenderScaleDoesNotTrap(value: Double) {
        let document = RenderFixtures.document([])
        let options = RenderOptions(scale: value)
        #expect(Renderer.pixelSize(for: document, options: options).width == 0)
        #expect(throws: RenderError.self) {
            try Renderer().image(for: document, baseImage: RenderFixtures.solidImage(.white), options: options)
        }
    }

    @Test func invalidPaddingCannotTrapCompositor() {
        let background = Document.Background(fill: .solid(color: .white), padding: 1e100)
        #expect(throws: ProjectFileError.invalidGeometry("background geometry")) {
            try BackgroundCompositor.render(RenderFixtures.solidImage(.white), background: background)
        }
    }

    @Test func invalidEffectSizesAreRejectedBeforeDrawing() {
        for kind in [Annotation.Kind.pixelate(rect: CGRect(x: 0, y: 0, width: 10, height: 10),
                                              blockSize: Int.max, randomize: false),
                     .blur(rect: CGRect(x: 0, y: 0, width: 10, height: 10), mode: .secure, radius: 1e100)] {
            let document = RenderFixtures.document([Annotation(kind: kind)])
            #expect(throws: ProjectFileError.invalidGeometry("annotation geometry")) {
                try Renderer().image(for: document, baseImage: RenderFixtures.solidImage(.white),
                                     options: RenderOptions(scale: 2))
            }
        }
    }

    @Test func scaledOutputIsCappedBeforeAllocation() {
        let document = Document(baseImage: .init(pixelWidth: 65536, pixelHeight: 20, scale: 2))
        #expect(Renderer.pixelSize(for: document, options: RenderOptions(scale: 2)).width == 0)
        #expect(throws: ProjectFileError.invalidGeometry("rendered size")) {
            try Renderer().image(for: document, baseImage: RenderFixtures.solidImage(.white),
                                 options: RenderOptions(scale: 2))
        }
    }
}

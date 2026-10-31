import CoreGraphics
import Foundation
@testable import ScreenCapKit
import Testing

@Suite("Renderer")
struct RendererTests {
    private typealias Fix = RenderFixtures
    private let blue = RenderFixtures.blue
    private let green = RenderFixtures.green

    /// A mix of kinds that exercises text, shadow, opacity and layers.
    private var sampleDocument: Document {
        var shadowed = Fix.annotation(.rectangle(rect: CGRect(x: 120, y: 120, width: 50, height: 40),
                                               filled: true, cornerRadius: 6), fill: green)
        shadowed.style.shadow = Document.Shadow()
        var faded = Fix.annotation(.ellipse(rect: CGRect(x: 10, y: 120, width: 60, height: 60)), fill: blue)
        faded.style.opacity = 0.5
        return Fix.document([
            Fix.annotation(.arrow(start: CGPoint(x: 20, y: 20), end: CGPoint(x: 160, y: 60), style: .tapered)),
            Fix.annotation(.text(string: "Step one", preset: 3, fontSize: 18,
                               rect: CGRect(x: 20, y: 70, width: 150, height: 30))),
            Fix.annotation(.counter(number: 2, center: CGPoint(x: 180, y: 20), radius: 14)),
            shadowed,
            faded
        ])
    }

    @Test func doubleScaleIsExactlyDoubleSize() throws {
        let base = Fix.solidImage(.white)
        let one = try Renderer().image(for: sampleDocument, baseImage: base, options: RenderOptions(scale: 1))
        let two = try Renderer().image(for: sampleDocument, baseImage: base, options: RenderOptions(scale: 2))
        #expect(two.width == one.width * 2 && two.height == one.height * 2)
        // Solid interiors land on the same color at the doubled position.
        let small = RenderedPixels(one)
        let large = RenderedPixels(two)
        for (x, y) in [(145, 140), (5, 5), (100, 190)] {
            #expect(small[x, y] == large[x * 2, y * 2], "pixel (\(x), \(y))")
        }
    }

    @Test(arguments: [1.0, 2.0])
    func imageMatchesDrawingIntoCallerContext(scale: Double) throws {
        let base = Fix.solidImage(.white)
        let options = RenderOptions(scale: scale)
        let renderer = Renderer()
        let viaImage = try renderer.image(for: sampleDocument, baseImage: base, options: options)

        let size = Renderer.pixelSize(for: sampleDocument, options: options)
        let context = try #require(CGContext(
            data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        renderer.draw(sampleDocument, baseImage: base, options: options, in: context)
        let viaContext = try #require(context.makeImage())
        #expect(RenderedPixels(viaImage) == RenderedPixels(viaContext))
    }

    @Test func drawsInZIndexOrder() throws {
        let rect = CGRect(x: 50, y: 50, width: 100, height: 100)
        let pixels = try Fix.render([
            Fix.annotation(.rectangle(rect: rect, filled: true, cornerRadius: 0), color: blue, zIndex: 1),
            Fix.annotation(.rectangle(rect: rect, filled: true, cornerRadius: 0), color: green, zIndex: 0)
        ])
        #expect(pixels[100, 100].matches(blue))
    }

    @Test func opacityBlendsWithBase() throws {
        var annotation = Fix.annotation(.rectangle(rect: CGRect(x: 50, y: 50, width: 100, height: 100),
                                                 filled: true, cornerRadius: 0))
        annotation.style.opacity = 0.5
        let pixels = try Fix.render([annotation])
        #expect(pixels[100, 100].matches(RGBAColor(red: 0.5, green: 0.5, blue: 1), tolerance: 4))
    }

    @Test func shadowOffsetPointsDownInModelSpace() throws {
        var annotation = Fix.annotation(.rectangle(rect: CGRect(x: 50, y: 50, width: 100, height: 50),
                                                 filled: true, cornerRadius: 0))
        annotation.style.shadow = Document.Shadow(color: .black, radius: 0, offset: CGSize(width: 0, height: 10))
        for scale in [1, 2] {
            let pixels = try Fix.render([annotation], options: RenderOptions(scale: Double(scale)))
            #expect(pixels[100 * scale, 105 * scale].matches(.black), "shadow below at \(scale)x")
            #expect(pixels[100 * scale, 45 * scale].matches(.white), "nothing above at \(scale)x")
        }
    }

    @Test func backgroundPadsAndOffsetsAnnotations() throws {
        let background = Document.Background(fill: .solid(color: green), padding: 20, cornerRadius: 0, shadow: nil)
        let document = Fix.document(
            [Fix.annotation(.rectangle(rect: CGRect(x: 0, y: 0, width: 10, height: 10),
                                       filled: true, cornerRadius: 0))],
            background: background, canvasSize: CGSize(width: 240, height: 240)
        )
        let base = Fix.solidImage(.white)

        let padded = RenderedPixels(try Renderer().image(for: document, baseImage: base))
        #expect(padded.width == 240 && padded.height == 240)
        #expect(padded[5, 5].matches(green))
        #expect(padded[25, 25].matches(blue), "annotations move with the base image")
        #expect(padded[100, 100].matches(.white))

        let bare = RenderedPixels(try Renderer().image(for: document, baseImage: base,
                                               options: RenderOptions(includeBackground: false)))
        #expect(bare.width == 200 && bare.height == 200)
        #expect(bare[5, 5].matches(blue))
    }

    @Test func backgroundAlignment() {
        let background = Document.Background(fill: .solid(color: green), padding: 10, alignment: .bottomRight)
        let document = Fix.document([], background: background, canvasSize: CGSize(width: 300, height: 260))
        let layout = Renderer.layout(for: document, options: RenderOptions())
        #expect(layout.imageFrame == CGRect(x: 90, y: 50, width: 200, height: 200))
    }

    @Test func gradientBackgroundRunsLeftToRight() throws {
        let fill = Document.BackgroundFill.linearGradient(
            stops: [.init(color: .black, location: 0), .init(color: .white, location: 1)], angle: 0
        )
        let document = Fix.document([], background: Document.Background(fill: fill, padding: 20, cornerRadius: 0,
                                                                      shadow: nil),
                                  canvasSize: CGSize(width: 240, height: 240))
        let pixels = RenderedPixels(try Renderer().image(for: document, baseImage: Fix.solidImage(.white)))
        #expect(pixels[1, 120].red < 20)
        #expect(pixels[238, 120].red > 235)
    }

    @Test func redactionHookGetsCanvasPixelGeometry() throws {
        let background = Document.Background(fill: .solid(color: .white), padding: 20, cornerRadius: 0, shadow: nil)
        let document = Fix.document([Fix.annotation(.pixelate(rect: CGRect(x: 10, y: 10, width: 30, height: 20),
                                                          blockSize: 8, randomize: false))],
                                  background: background, canvasSize: CGSize(width: 240, height: 240))
        let renderer = Renderer(redaction: PaintRectRedaction())
        let pixels = RenderedPixels(try renderer.image(for: document, baseImage: Fix.solidImage(.white),
                                               options: RenderOptions(scale: 2)))
        // Model (10, 10, 30, 20) + 20 padding, doubled: (60, 60, 60, 40).
        #expect(pixels[61, 61].matches(.black))
        #expect(pixels[118, 98].matches(.black))
        #expect(pixels[58, 70].matches(.white))
        #expect(pixels[122, 70].matches(.white))
    }

    @Test func invalidScaleThrows() {
        #expect(throws: RenderError.invalidScale(0)) {
            try Renderer().image(for: Fix.document([]), baseImage: Fix.solidImage(.white),
                                 options: RenderOptions(scale: 0))
        }
    }
}

/// Test hook: paints the pixelate rect black, flipping to CG's bottom-left origin.
private struct PaintRectRedaction: RedactionRenderer {
    func apply(_ kind: Annotation.Kind, to canvas: CGImage, scale: Double) -> CGImage? {
        guard case let .pixelate(rect, _, _) = kind,
              let context = CGContext(data: nil, width: canvas.width, height: canvas.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(canvas, in: CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
        context.setFillColor(RGBAColor.black.cgColor)
        context.fill(CGRect(x: rect.minX, y: Double(canvas.height) - rect.maxY, width: rect.width, height: rect.height))
        return context.makeImage()
    }
}

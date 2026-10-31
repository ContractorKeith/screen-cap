import CoreGraphics
@testable import ScreenCapKit
import Testing

@Suite("WindowShadow")
struct WindowShadowTests {
    /// A 100×80 canvas: transparent, a 20%-alpha "shadow" ring, and an opaque body at (10, 6, 70, 60).
    static func shadowedImage() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 0, alpha: 0.2))
        context.fill(CGRect(x: 4, y: 4, width: 92, height: 72))
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1))
        // CG y is bottom-up: top-left y = 80 - (14 + 60) = 6.
        context.fill(CGRect(x: 10, y: 14, width: 70, height: 60))
        return context.makeImage()
    }

    @Test func findsTheOpaqueBody() throws {
        let image = try #require(Self.shadowedImage())
        #expect(WindowShadow.opaqueBounds(of: image) == CGRect(x: 10, y: 6, width: 70, height: 60))
    }

    @Test func noOpaquePixelsGivesNil() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        #expect(WindowShadow.opaqueBounds(of: image) == nil)
    }

    @Test func enlargesSoTheBodyIsOneToOne() {
        // The body should be 140×120 px but measured 70×60 in a 100×80 canvas: double everything.
        let size = WindowShadow.fullSize(canvas: CGSize(width: 100, height: 80),
                                         body: CGRect(x: 10, y: 6, width: 70, height: 60),
                                         bodyPixels: CGSize(width: 140, height: 120))
        #expect(size == CGSize(width: 200, height: 160))
    }

    @Test func alreadyOneToOneNeedsNothing() {
        #expect(WindowShadow.fullSize(canvas: CGSize(width: 100, height: 80),
                                      body: CGRect(x: 0, y: 0, width: 100, height: 80),
                                      bodyPixels: CGSize(width: 100, height: 80)) == nil)
    }

    // MARK: - Symmetric trim (#100)

    /// 200×150 canvas: opaque body at (30, 20, 100, 80), a shadow spreading 16 left, 20 right,
    /// 8 up and 28 down, then 50 px of empty canvas on the right (what ScreenCaptureKit pads).
    static func lopsidedImage() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 200, height: 150, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Shadow, top-left (14, 12) to (150, 128): CG y = 150 - 128 = 22.
        context.setFillColor(CGColor(gray: 0, alpha: 0.2))
        context.fill(CGRect(x: 14, y: 22, width: 136, height: 116))
        // Body, top-left (30, 20, 100, 80): CG y = 150 - 100 = 50.
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 30, y: 50, width: 100, height: 80))
        return context.makeImage()
    }

    @Test func symmetricFrameUsesTheWiderSpreadPerAxis() {
        let frame = WindowShadow.symmetricFrame(body: CGRect(x: 30, y: 20, width: 100, height: 80),
                                                shadow: CGRect(x: 14, y: 12, width: 136, height: 116))
        #expect(frame == CGRect(x: 10, y: -8, width: 140, height: 136))
    }

    @Test func trimGivesEqualMarginsAroundTheBody() throws {
        let image = try #require(Self.lopsidedImage())
        let trimmed = try #require(WindowShadow.trimmed(image))
        #expect(trimmed.width == 140 && trimmed.height == 136)
        let body = try #require(WindowShadow.opaqueBounds(of: trimmed))
        #expect(body == CGRect(x: 20, y: 28, width: 100, height: 80))
        #expect(body.minX == CGFloat(trimmed.width) - body.maxX)
        #expect(body.minY == CGFloat(trimmed.height) - body.maxY)
        // The shadow itself is kept: nothing with alpha was cut off.
        #expect(WindowShadow.shadowBounds(of: trimmed) == CGRect(x: 4, y: 20, width: 136, height: 116))
    }

    @Test func alreadySymmetricNeedsNoTrim() throws {
        let image = try #require(Self.shadowedImage())
        let trimmed = try #require(WindowShadow.trimmed(image))
        // Ring spreads 6 left, 16 right, 2 up, 10 down around the body: 16 and 10 per axis.
        #expect(WindowShadow.opaqueBounds(of: trimmed) == CGRect(x: 16, y: 10, width: 70, height: 60))
        #expect(WindowShadow.trimmed(trimmed) == nil)
    }

    @Test func bodyIsMeasuredPastTranslucentSidebars() throws {
        // A translucent strip through the center row must not shrink the measured body.
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 10, y: 10, width: 80, height: 60))
        context.clear(CGRect(x: 10, y: 20, width: 20, height: 40))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.6))
        context.fill(CGRect(x: 10, y: 20, width: 20, height: 40))
        let image = try #require(context.makeImage())
        #expect(WindowShadow.opaqueBounds(of: image) == CGRect(x: 10, y: 10, width: 80, height: 60))
    }

    @Test func windowWithBackgroundIsCentered() throws {
        let lopsided = try #require(Self.lopsidedImage())
        let image = try #require(WindowShadow.trimmed(lopsided))
        let background = Document.Background(fill: .solid(color: RGBAColor(red: 1, green: 0, blue: 0, alpha: 1)),
                                             padding: 32, cornerRadius: 0, shadow: nil)
        let output = try BackgroundCompositor.render(image, background: background)
        let body = try #require(Self.bounds(of: output) { $0[2] > 60 && $0[0] < 60 })
        #expect(body.minX == CGFloat(output.width) - body.maxX)
        #expect(body.minY == CGFloat(output.height) - body.maxY)
    }

    /// Bounding box (top-left pixels) of the RGBA pixels passing `test`.
    static func bounds(of image: CGImage, where test: ([UInt8]) -> Bool) -> CGRect? {
        let width = image.width, height = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var rect = CGRect.null
        for row in 0..<height {
            for column in 0..<width {
                let index = (row * width + column) * 4
                if test([bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3]]) {
                    rect = rect.union(CGRect(x: column, y: row, width: 1, height: 1))
                }
            }
        }
        return rect.isNull ? nil : rect
    }
}

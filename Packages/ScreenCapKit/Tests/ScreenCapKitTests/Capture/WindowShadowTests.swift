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
}

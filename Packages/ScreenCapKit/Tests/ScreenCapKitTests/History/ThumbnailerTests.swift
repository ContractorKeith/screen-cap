import CoreGraphics
@testable import ScreenCapKit
import Testing

@Suite("Thumbnailer")
struct ThumbnailerTests {
    @Test func scalesDownToMaxWidthKeepingAspect() throws {
        let image = HistoryFixtures.image(width: 1024, height: 600)
        let thumb = try #require(Thumbnailer.make(image, maxWidth: 256))
        #expect(thumb.width == 256)
        #expect(thumb.height == 150)
    }

    @Test func neverUpscales() throws {
        let image = HistoryFixtures.image(width: 100, height: 40)
        let thumb = try #require(Thumbnailer.make(image, maxWidth: 256))
        #expect(thumb.width == 100)
        #expect(thumb.height == 40)
    }

    @Test func slimImageKeepsAtLeastOnePixel() throws {
        let thumb = try #require(Thumbnailer.make(HistoryFixtures.image(width: 2000, height: 1), maxWidth: 256))
        #expect(thumb.width >= 1)
        #expect(thumb.height == 1)
    }

    // MARK: - Long captures (#133)

    @Test func squareImageIsNotCropped() {
        #expect(Thumbnailer.elongation(width: 1000, height: 1000) == nil)
        #expect(Thumbnailer.cropRect(width: 1000, height: 1000) == CGRect(x: 0, y: 0, width: 1000, height: 1000))
    }

    @Test func ordinaryScreenshotsAreNotCropped() {
        #expect(Thumbnailer.elongation(width: 2880, height: 1800) == nil)
        #expect(Thumbnailer.elongation(width: 1000, height: 3000) == nil) // exactly 1:3 stays whole
    }

    @Test func tallImageCropsToTheTopAtCellAspect() {
        #expect(Thumbnailer.elongation(width: 600, height: 6000) == .tall)
        // 600 / (4/3) = 450 rows from the top.
        #expect(Thumbnailer.cropRect(width: 600, height: 6000) == CGRect(x: 0, y: 0, width: 600, height: 450))
    }

    @Test func wideImageCropsToTheLeadingEdgeAtCellAspect() {
        #expect(Thumbnailer.elongation(width: 6000, height: 600) == .wide)
        // 600 * 4/3 = 800 columns from the left.
        #expect(Thumbnailer.cropRect(width: 6000, height: 600) == CGRect(x: 0, y: 0, width: 800, height: 600))
    }

    @Test func tallThumbnailIsReadableAndShowsTheTop() throws {
        // Red top 600 rows, blue below: the thumbnail must be all red.
        let image = try #require(Self.split(width: 600, height: 6000, topRows: 600))
        let thumb = try #require(Thumbnailer.make(image, maxWidth: 256))
        #expect(thumb.width == 256)
        #expect(thumb.height == 192) // 256 / (4/3), not a 26 px sliver
        let pixel = try #require(Self.pixel(of: thumb, x: 128, y: thumb.height - 2))
        #expect(pixel.red > 200 && pixel.blue < 50)
    }

    @Test func wideThumbnailIsReadable() throws {
        let thumb = try #require(Thumbnailer.make(HistoryFixtures.image(width: 6000, height: 600), maxWidth: 256))
        #expect(thumb.width == 256)
        #expect(thumb.height == 192)
    }

    @Test func narrowTallImageIsCroppedWithoutUpscaling() throws {
        let thumb = try #require(Thumbnailer.make(HistoryFixtures.image(width: 120, height: 1200), maxWidth: 256))
        #expect(thumb.width == 120)
        #expect(thumb.height == 90)
    }

    /// An image with `topRows` red rows at the top and blue below.
    private static func split(width: Int, height: Int, topRows: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        // CGContext's origin is bottom-left, so the top rows sit at the high y values.
        context.fill(CGRect(x: 0, y: height - topRows, width: width, height: topRows))
        return context.makeImage()
    }

    /// RGBA at (`x`, `y`) with y counted from the top.
    private static func pixel(of image: CGImage, x: Int, y: Int) -> (red: UInt8, blue: UInt8)? {
        var data = [UInt8](repeating: 0, count: 4)
        let drawn = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            let origin = CGPoint(x: -x, y: -(image.height - 1 - y))
            context.draw(image, in: CGRect(origin: origin, size: CGSize(width: image.width, height: image.height)))
            return true
        }
        return drawn ? (data[0], data[2]) : nil
    }

    @Test func rejectsZeroWidth() {
        #expect(Thumbnailer.make(HistoryFixtures.image(width: 10, height: 10), maxWidth: 0) == nil)
    }
}

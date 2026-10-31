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

    @Test func tallSlimImageKeepsAtLeastOnePixel() throws {
        let thumb = try #require(Thumbnailer.make(HistoryFixtures.image(width: 2000, height: 1), maxWidth: 256))
        #expect(thumb.width == 256)
        #expect(thumb.height == 1)
    }

    @Test func rejectsZeroWidth() {
        #expect(Thumbnailer.make(HistoryFixtures.image(width: 10, height: 10), maxWidth: 0) == nil)
    }
}

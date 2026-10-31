import CoreGraphics
import Foundation
@testable import ScreenCapKit
import Testing

/// A test pattern where each pixel encodes its own position: R = x, G = y, B = 7, opaque.
private func makePattern(width: Int, height: Int) throws -> CGImage {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for row in 0..<height {
        for column in 0..<width {
            let offset = (row * width + column) * 4
            bytes[offset] = UInt8(column)
            bytes[offset + 1] = UInt8(row)
            bytes[offset + 2] = 7
            bytes[offset + 3] = 255
        }
    }
    let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    return try #require(CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: space,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
    ))
}

/// RGBA bytes of `image`, top row first, read back through a same-format bitmap context.
private struct Pixels {
    let width: Int
    let bytes: [UInt8]

    init(_ image: CGImage) throws {
        width = image.width
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        try buffer.withUnsafeMutableBytes { raw in
            let context = try #require(CGContext(
                data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        bytes = buffer
    }

    /// (R, G, B) at a pixel; for the pattern that is (source x, source y, 7).
    func rgb(_ x: Int, _ y: Int) -> [UInt8] {
        let offset = (y * width + x) * 4
        return Array(bytes[offset..<offset + 3])
    }
}

private func source(_ x: Int, _ y: Int) -> [UInt8] { [UInt8(x), UInt8(y), 7] }

@Suite("ImageCropper")
struct ImageCropperTests {
    /// A 64x48 pt display captured at `scale`; crop a point rect and check every corner and the center.
    @Test(arguments: [1, 2])
    func pixelExactCrop(scale: Int) throws {
        let display = DisplayInfo(
            id: 1, frame: CGRect(x: 0, y: 0, width: 64, height: 48), backingScale: CGFloat(scale)
        )
        let still = try makePattern(width: 64 * scale, height: 48 * scale)

        // 10 pt from the left, 8 pt from the bottom: the top edge is 48 - 20 = 28 pt from the top.
        let pixelRect = display.pixelRect(forGlobalPoints: CGRect(x: 10, y: 8, width: 20, height: 12))
        let left = 10 * scale, top = 28 * scale, width = 20 * scale, height = 12 * scale
        #expect(pixelRect == CGRect(x: left, y: top, width: width, height: height))

        let cropped = try #require(ImageCropper.crop(still, pixelRect: pixelRect))
        #expect(cropped.width == width)
        #expect(cropped.height == height)

        let pixels = try Pixels(cropped)
        #expect(pixels.rgb(0, 0) == source(left, top))
        #expect(pixels.rgb(width - 1, 0) == source(left + width - 1, top))
        #expect(pixels.rgb(0, height - 1) == source(left, top + height - 1))
        #expect(pixels.rgb(width - 1, height - 1) == source(left + width - 1, top + height - 1))
        #expect(pixels.rgb(width / 2, height / 2) == source(left + width / 2, top + height / 2))
    }

    @Test func clipsToImageAndRejectsEmpty() throws {
        let still = try makePattern(width: 40, height: 30)
        let clipped = try #require(ImageCropper.crop(still, pixelRect: CGRect(x: 30, y: -5, width: 20, height: 15)))
        #expect(clipped.width == 10)
        #expect(clipped.height == 10)
        #expect(try Pixels(clipped).rgb(0, 0) == source(30, 0))

        #expect(ImageCropper.crop(still, pixelRect: CGRect(x: 50, y: 0, width: 10, height: 10)) == nil)
        #expect(ImageCropper.crop(still, pixelRect: CGRect(x: 5, y: 5, width: 0, height: 10)) == nil)
    }

    /// Frozen-screen path: crop a 2x display still that sits left of and above the primary.
    @Test func capturedImageCropsByGlobalPoints() throws {
        let frame = CGRect(x: -64, y: 100, width: 64, height: 48)
        let pattern = try makePattern(width: 128, height: 96)
        let still = CapturedImage(cgImage: pattern, scale: 2, pointRect: frame, displayID: 5)
        #expect(still.pixelSize == CGSize(width: 128, height: 96))

        // Overhangs the display's right edge; clipped to x < 0.
        let area = try #require(still.cropped(toGlobalPoints: CGRect(x: -20, y: 120, width: 40, height: 10)))
        #expect(area.pointRect == CGRect(x: -20, y: 120, width: 20, height: 10))
        #expect(area.pixelSize == CGSize(width: 40, height: 20))
        #expect(area.scale == 2)
        #expect(area.displayID == 5)
        // Left edge 44 pt in, top edge 148 - 130 = 18 pt down.
        let pixels = try Pixels(area.cgImage)
        #expect(pixels.rgb(0, 0) == source(88, 36))
        #expect(pixels.rgb(39, 19) == source(127, 55))

        #expect(still.cropped(toGlobalPoints: CGRect(x: 10, y: 10, width: 5, height: 5)) == nil)
    }
}

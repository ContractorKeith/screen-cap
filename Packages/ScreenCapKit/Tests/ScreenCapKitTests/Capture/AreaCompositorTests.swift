import CoreGraphics
import Foundation
@testable import ScreenCapKit
import Testing

@Suite("AreaCompositor")
struct AreaCompositorTests {
    /// A solid opaque image.
    static func solid(width: Int, height: Int, _ rgb: [UInt8]) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for pixel in 0..<(width * height) {
            bytes[pixel * 4] = rgb[0]
            bytes[pixel * 4 + 1] = rgb[1]
            bytes[pixel * 4 + 2] = rgb[2]
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        return try #require(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }

    /// RGBA at (x, y), y counted from the top row.
    static func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = (y * image.width + x) * 4
        return Array(bytes[offset..<offset + 4])
    }

    /// Retina 100×100 pt display on the left (red), 1x 100×100 pt display on the right (green).
    static func sideBySide() throws -> (DisplayGeometry, [CapturedImage]) {
        let left = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), backingScale: 2)
        let right = DisplayInfo(id: 2, frame: CGRect(x: 100, y: 0, width: 100, height: 100), backingScale: 1)
        let stills = [
            CapturedImage(cgImage: try solid(width: 200, height: 200, [255, 0, 0]), scale: 2,
                          pointRect: left.frame, displayID: 1),
            CapturedImage(cgImage: try solid(width: 100, height: 100, [0, 255, 0]), scale: 1,
                          pointRect: right.frame, displayID: 2)
        ]
        return (DisplayGeometry(displays: [left, right]), stills)
    }

    @Test func spanningRectIsCompositedAtTheHighestScale() throws {
        let (geometry, stills) = try Self.sideBySide()
        let rect = CGRect(x: 50, y: 20, width: 100, height: 40)
        let image = try #require(AreaCompositor.image(of: rect, geometry: geometry, stills: stills))
        #expect(image.scale == 2)
        #expect(image.pointRect == rect)
        #expect(image.cgImage.width == 200)
        #expect(image.cgImage.height == 80)
        #expect(try Self.pixel(image.cgImage, x: 10, y: 40) == [255, 0, 0, 255])
        #expect(try Self.pixel(image.cgImage, x: 99, y: 40) == [255, 0, 0, 255])
        #expect(try Self.pixel(image.cgImage, x: 101, y: 40) == [0, 255, 0, 255])
        #expect(try Self.pixel(image.cgImage, x: 190, y: 40) == [0, 255, 0, 255])
    }

    @Test func stackedDisplaysKeepTheirVerticalOrder() throws {
        // Display 2 sits above display 1; global y grows up, image rows grow down.
        let bottom = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), backingScale: 1)
        let top = DisplayInfo(id: 2, frame: CGRect(x: 0, y: 100, width: 100, height: 100), backingScale: 1)
        let stills = [
            CapturedImage(cgImage: try Self.solid(width: 100, height: 100, [255, 0, 0]), scale: 1,
                          pointRect: bottom.frame, displayID: 1),
            CapturedImage(cgImage: try Self.solid(width: 100, height: 100, [0, 0, 255]), scale: 1,
                          pointRect: top.frame, displayID: 2)
        ]
        let geometry = DisplayGeometry(displays: [bottom, top])
        let image = try #require(AreaCompositor.image(of: CGRect(x: 10, y: 50, width: 20, height: 100),
                                                      geometry: geometry, stills: stills))
        #expect(image.cgImage.height == 100)
        #expect(try Self.pixel(image.cgImage, x: 5, y: 10) == [0, 0, 255, 255])
        #expect(try Self.pixel(image.cgImage, x: 5, y: 90) == [255, 0, 0, 255])
    }

    @Test func singleDisplayIsAPlainCrop() throws {
        let (geometry, stills) = try Self.sideBySide()
        let image = try #require(AreaCompositor.image(of: CGRect(x: 10, y: 10, width: 30, height: 20),
                                                      geometry: geometry, stills: stills))
        #expect(image.scale == 2)
        #expect(image.displayID == 1)
        #expect(image.cgImage.width == 60)
    }

    @Test func missingStillOrOffScreenGivesNil() throws {
        let (geometry, stills) = try Self.sideBySide()
        let spanning = CGRect(x: 50, y: 20, width: 100, height: 40)
        #expect(AreaCompositor.image(of: spanning, geometry: geometry, stills: [stills[0]]) == nil)
        #expect(AreaCompositor.image(of: CGRect(x: 500, y: 500, width: 10, height: 10),
                                     geometry: geometry, stills: stills) == nil)
    }
}

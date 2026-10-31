import CoreGraphics
import Foundation
@testable import ScreenCapKit

/// RGBA8 pixels read back from a CGImage, row 0 at the top.
struct RenderedPixels: Equatable {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        bytes = buffer
    }

    struct RGBA: Equatable, CustomStringConvertible {
        var red: Int, green: Int, blue: Int, alpha: Int
        var description: String { "(\(red), \(green), \(blue), \(alpha))" }

        /// True when every channel is within `tolerance` of `color`'s 0...255 value.
        func matches(_ color: RGBAColor, tolerance: Int = 8) -> Bool {
            abs(red - Int(color.red * 255)) <= tolerance && abs(green - Int(color.green * 255)) <= tolerance
                && abs(blue - Int(color.blue * 255)) <= tolerance && abs(alpha - Int(color.alpha * 255)) <= tolerance
        }
    }

    subscript(x: Int, y: Int) -> RGBA {
        let index = (y * width + x) * 4
        return RGBA(red: Int(bytes[index]), green: Int(bytes[index + 1]),
                    blue: Int(bytes[index + 2]), alpha: Int(bytes[index + 3]))
    }

    /// RenderedPixels in `rect` that are not white.
    func inkCount(in rect: CGRect) -> Int {
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) where !self[x, y].matches(.white, tolerance: 24) {
                count += 1
            }
        }
        return count
    }
}

enum RenderFixtures {
    static let blue = RGBAColor(red: 0, green: 0, blue: 1)
    static let green = RGBAColor(red: 0, green: 1, blue: 0)
    static let size = 200

    /// A solid image, `size` × `size` unless given.
    static func solidImage(_ color: RGBAColor, width: Int = size, height: Int = size) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Top half red, bottom half green, so tests can tell if an image is upside down.
    static func twoToneImage() -> CGImage {
        let context = CGContext(
            data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(RGBAColor(red: 1, green: 0, blue: 0).cgColor)
        context.fill(CGRect(x: 0, y: 10, width: 20, height: 10)) // CG y-up: top half
        context.setFillColor(green.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        return context.makeImage()!
    }

    static func document(_ annotations: [Annotation], background: Document.Background? = nil,
                         canvasSize: CGSize? = nil) -> Document {
        Document(baseImage: Document.BaseImage(pixelWidth: size, pixelHeight: size, scale: 1),
                 canvasSize: canvasSize, background: background, annotations: annotations)
    }

    static func annotation(_ kind: Annotation.Kind, color: RGBAColor = blue, width: Double = 4,
                           fill: RGBAColor? = nil, zIndex: Int = 0) -> Annotation {
        Annotation(zIndex: zIndex, style: Annotation.Style(strokeColor: color, strokeWidth: width, fillColor: fill),
                   kind: kind)
    }

    /// Renders `annotations` on a white 200 × 200 base.
    static func render(_ annotations: [Annotation], layers: [String: CGImage] = [:],
                       renderer: Renderer = Renderer(),
                       options: RenderOptions = RenderOptions()) throws -> RenderedPixels {
        let image = try renderer.image(for: document(annotations), baseImage: solidImage(.white),
                                       layers: layers, options: options)
        return RenderedPixels(image)
    }
}

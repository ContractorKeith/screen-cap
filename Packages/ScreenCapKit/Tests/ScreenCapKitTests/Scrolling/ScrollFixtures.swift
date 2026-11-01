import CoreGraphics
import Foundation
@testable import ScreenCapKit

/// Deterministic PRNG (SplitMix64) so synthetic pages are the same on every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58_476d_1ce4_e5b9
        value = (value ^ (value >> 27)) &* 0x94d0_49bb_1331_11eb
        return value ^ (value >> 31)
    }
}

/// Synthetic scroll content as lines (rows for vertical, columns for horizontal) of opaque
/// RGBA pixels packed as UInt32 in memory byte order.
enum ScrollFixtures {
    typealias Line = [UInt32]

    static func pixel(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> UInt32 {
        UInt32(red) | UInt32(green) << 8 | UInt32(blue) << 16 | 0xff00_0000
    }

    /// A page of distinctive 60-line color bands. Each band opens with 4 blank lines (blank
    /// space matches at any offset, like real pages); the rest carries text-like dark speckles.
    static func page(length: Int, breadth: Int, seed: UInt64) -> [Line] {
        var random = SeededGenerator(seed: seed)
        var bandColor = pixel(255, 255, 255)
        return (0..<length).map { index in
            if index % 60 == 0 {
                bandColor = pixel(.random(in: 150...255, using: &random), .random(in: 150...255, using: &random),
                                  .random(in: 150...255, using: &random))
            }
            var line = Line(repeating: bandColor, count: breadth)
            guard index % 60 >= 4 else { return line }
            var position = Int.random(in: 0..<8, using: &random)
            while position < breadth {
                let run = Int.random(in: 1...4, using: &random)
                let ink = UInt8.random(in: 0...90, using: &random)
                for offset in position..<min(breadth, position + run) { line[offset] = pixel(ink, ink, ink) }
                position += run + Int.random(in: 2...14, using: &random)
            }
            return line
        }
    }

    /// Viewport frames scrolled by `step`, with fixed `header` and `footer` lines drawn on each.
    /// The last frame is clamped to the end of the page.
    static func frames(page: [Line], viewport: Int, header: [Line], footer: [Line], step: Int) -> [[Line]] {
        let visible = viewport - header.count - footer.count
        var starts = Array(stride(from: 0, to: page.count - visible, by: step))
        starts.append(page.count - visible)
        return starts.map { header + page[$0..<$0 + visible] + footer }
    }

    /// Builds an image whose lines along `axis` are `lines`.
    static func image(lines: [Line], axis: ScrollAxis) -> CGImage {
        let length = lines.count
        let breadth = lines.first?.count ?? 0
        let width = axis == .vertical ? breadth : length
        let height = axis == .vertical ? length : breadth
        var pixels = [UInt32](repeating: 0, count: width * height)
        for (lineIndex, line) in lines.enumerated() {
            for (index, value) in line.enumerated() {
                let offset = axis == .vertical ? lineIndex * width + index : index * width + lineIndex
                pixels[offset] = value
            }
        }
        let data = pixels.withUnsafeBytes { Data($0) }
        // Fixture sizes are always valid, so these force unwraps cannot fail.
        // swiftlint:disable force_unwrapping
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )!
        // swiftlint:enable force_unwrapping
    }

    /// Reads `image` back as lines along `axis`, through an independent sRGB RGBA bitmap.
    static func lines(of image: CGImage, axis: ScrollAxis) -> [Line] {
        let width = image.width
        let height = image.height
        var pixels = [UInt32](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.setBlendMode(.copy)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let length = axis == .vertical ? height : width
        let breadth = axis == .vertical ? width : height
        // Vertical lines are rows: copy them whole, a per-pixel map is slow in debug (#140).
        if axis == .vertical {
            return (0..<length).map { Array(pixels[$0 * width..<($0 + 1) * width]) }
        }
        return (0..<length).map { lineIndex in
            (0..<breadth).map { index in pixels[index * width + lineIndex] }
        }
    }

    /// A list of `rows` text rows spread over `length` lines (rows 18 or 19 lines tall at 80 rows
    /// over 1500), every row drawn from the same "glyphs", like a log or Terminal repeating one line.
    /// With `ruleEvery`, every n-th row is a horizontal rule instead, like a table.
    static func repetitiveList(rows: Int, length: Int, breadth: Int, ruleEvery: Int? = nil) -> [Line] {
        var random = SeededGenerator(seed: 21)
        let white = pixel(255, 255, 255)
        let ink = pixel(30, 30, 30)
        // One row of text: 12 lines of speckled glyphs, then blank space.
        let glyphs: [Line] = (0..<12).map { _ in
            (0..<breadth).map { index in
                let isText = index > 8 && index < breadth * 2 / 3
                return isText && Int.random(in: 0..<3, using: &random) == 0 ? ink : white
            }
        }
        let rule = Line(repeating: pixel(120, 120, 120), count: breadth)
        let blank = Line(repeating: white, count: breadth)
        return (0..<length).map { line in
            let row = line * rows / length
            let top = row * length / rows + (row * length % rows == 0 ? 0 : 1)
            let inRow = line - top
            if let ruleEvery, row % ruleEvery == ruleEvery - 1 {
                return inRow == 8 ? rule : blank
            }
            return inRow >= 2 && inRow < 14 ? glyphs[inRow - 2] : blank
        }
    }

    /// Solid header/footer-style lines with their own speckle pattern.
    static func bar(length: Int, breadth: Int, seed: UInt64) -> [Line] {
        page(length: length, breadth: breadth, seed: seed).map { line in line.map { $0 ^ 0x0030_0000 } }
    }
}

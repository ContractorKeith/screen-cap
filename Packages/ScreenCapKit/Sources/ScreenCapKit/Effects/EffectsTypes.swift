// Small value types and pixel helpers shared by the Effects module.
// Colors, shadows, gradient stops, alignment and spotlight shapes come from the Document model.
import CoreGraphics
import Foundation

/// Errors thrown by effect renderers.
public enum EffectsError: Error, Equatable {
    case contextCreationFailed
    case imageCreationFailed
}

/// Per-edge distances in image pixels.
public struct EffectsInsets: Equatable, Sendable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat

    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public init(all value: CGFloat) {
        self.init(top: value, left: value, bottom: value, right: value)
    }

    public static let zero = EffectsInsets(all: 0)
}

/// SplitMix64: tiny, fast, seedable PRNG so redaction output is reproducible for a given seed.
struct EffectsRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    /// Uniform integer in `range` (inclusive).
    mutating func int(in range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &self)
    }
}

/// An 8-bit RGBA (premultiplied, sRGB) bitmap context. Memory row 0 is the top row of the image,
/// so `(x, y)` addressing uses top-left-origin pixel coordinates.
struct EffectsBitmap {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    let context: CGContext
    let width: Int
    let height: Int

    init(width: Int, height: Int) throws {
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: Self.colorSpace, bitmapInfo: Self.bitmapInfo
              ), context.data != nil
        else { throw EffectsError.contextCreationFailed }
        self.context = context
        self.width = width
        self.height = height
    }

    /// A bitmap holding a copy of `image` at its native pixel size.
    init(image: CGImage) throws {
        try self.init(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    var bytesPerRow: Int { context.bytesPerRow }

    var pixels: UnsafeMutablePointer<UInt8> {
        // Non-nil is checked in init.
        context.data.unsafelyUnwrapped.assumingMemoryBound(to: UInt8.self)
    }

    /// Byte offset of pixel `(x, y)` in top-left coordinates.
    func offset(x: Int, y: Int) -> Int {
        y * bytesPerRow + x * 4
    }

    /// Converts a top-left-origin rect to Core Graphics' bottom-left-origin space.
    func cgRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height)
    }

    func makeImage() throws -> CGImage {
        guard let image = context.makeImage() else { throw EffectsError.imageCreationFailed }
        return image
    }
}

extension Annotation.SpotlightShape {
    /// The shape's path in Core Graphics space for a bitmap of the given height.
    func cgPath(in bitmap: EffectsBitmap) -> CGPath {
        switch self {
        case .rect(let rect):
            return CGPath(rect: bitmap.cgRect(rect), transform: nil)
        case .ellipse(let rect):
            return CGPath(ellipseIn: bitmap.cgRect(rect), transform: nil)
        }
    }
}

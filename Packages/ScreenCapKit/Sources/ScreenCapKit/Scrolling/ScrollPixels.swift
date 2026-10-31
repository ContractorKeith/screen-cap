// Shared pixel plumbing for scrolling capture: axis, RGBA frames, line hashes, line copies.
import CoreGraphics

/// The direction content moves while scrolling.
public enum ScrollAxis: String, Sendable, Codable, CaseIterable {
    /// Lines are rows; scrolling moves content up.
    case vertical
    /// Lines are columns; scrolling moves content left.
    case horizontal
}

/// Hash of one line (row or column) plus whether it carries any detail.
struct LineHash: Equatable {
    let value: UInt64
    /// False when every sampled pixel is the same color (blank space matches anything).
    let isInformative: Bool
}

/// An image redrawn into a 32-bit RGBA bitmap so pixels can be read and copied directly.
/// Memory row 0 is the top row of the image.
final class PixelFrame {
    let context: CGContext
    let width: Int
    let height: Int

    /// Allocates a blank bitmap. Returns nil for an empty size.
    init?(width: Int, height: Int, colorSpace: CGColorSpace) {
        guard width > 0, height > 0, let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), context.data != nil else { return nil }
        self.context = context
        self.width = width
        self.height = height
    }

    /// Redraws `image` at its own pixel size.
    convenience init?(image: CGImage, colorSpace: CGColorSpace? = nil) {
        let space = colorSpace ?? PixelFrame.workingSpace(for: image)
        self.init(width: image.width, height: image.height, colorSpace: space)
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    /// The image's own RGB color space, or sRGB when it has none usable.
    static func workingSpace(for image: CGImage) -> CGColorSpace {
        if let space = image.colorSpace, space.model == .rgb { return space }
        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    var bytesPerRow: Int { context.bytesPerRow }

    var pixels: UnsafeMutablePointer<UInt32> {
        // Non-nil by construction (checked in init).
        context.data!.assumingMemoryBound(to: UInt32.self) // swiftlint:disable:this force_unwrapping
    }

    /// Number of lines along `axis` (height for vertical, width for horizontal).
    func length(along axis: ScrollAxis) -> Int { axis == .vertical ? height : width }

    /// Pixels per line along `axis` (width for vertical, height for horizontal).
    func breadth(along axis: ScrollAxis) -> Int { axis == .vertical ? width : height }

    /// Hashes every line along `axis`, sampling at most ~512 pixels per line for speed.
    func lineHashes(along axis: ScrollAxis) -> [LineHash] {
        let count = length(along: axis)
        let breadth = breadth(along: axis)
        let step = max(1, breadth / 512)
        let rowPixels = bytesPerRow / 4
        let base = pixels
        return (0..<count).map { line in
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325 // FNV-1a offset basis
            var first: UInt32?
            var uniform = true
            for index in stride(from: 0, to: breadth, by: step) {
                let pixel = axis == .vertical ? base[line * rowPixels + index] : base[index * rowPixels + line]
                if let first, first != pixel { uniform = false } else if first == nil { first = pixel }
                hash = (hash ^ UInt64(pixel)) &* 0x0000_0100_0000_01b3
            }
            return LineHash(value: hash, isInformative: !uniform)
        }
    }
}

extension PixelFrame {
    /// Copies `lines` along `axis` into `destination` (same breadth), starting at line `start`.
    func copyLines(_ lines: Range<Int>, along axis: ScrollAxis, to destination: PixelFrame, at start: Int) {
        guard !lines.isEmpty else { return }
        let breadth = breadth(along: axis)
        let sourceRow = bytesPerRow / 4
        let destinationRow = destination.bytesPerRow / 4
        let source = pixels
        let target = destination.pixels
        switch axis {
        case .vertical:
            for offset in 0..<lines.count {
                (target + (start + offset) * destinationRow)
                    .update(from: source + (lines.lowerBound + offset) * sourceRow, count: breadth)
            }
        case .horizontal:
            for row in 0..<breadth {
                (target + row * destinationRow + start)
                    .update(from: source + row * sourceRow + lines.lowerBound, count: lines.count)
            }
        }
    }
}

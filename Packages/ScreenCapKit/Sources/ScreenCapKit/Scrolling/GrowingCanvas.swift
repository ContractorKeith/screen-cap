// Growing bitmap the stitcher appends strips to (PLAN §5.4 step 5).
import CoreGraphics

/// An RGBA bitmap that grows along the scroll axis in doubling chunks, so appending stays
/// linear overall instead of copying the whole image on every frame.
final class GrowingCanvas {
    let axis: ScrollAxis
    let breadth: Int
    let colorSpace: CGColorSpace
    let maxLength: Int
    private(set) var length = 0
    private var storage: PixelFrame?

    init(axis: ScrollAxis, breadth: Int, colorSpace: CGColorSpace?, maxLength: Int) {
        self.axis = axis
        self.breadth = breadth
        self.colorSpace = colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        self.maxLength = maxLength
    }

    private var capacity: Int { storage?.length(along: axis) ?? 0 }

    /// Copies `lines` of `frame` onto the end of the canvas.
    func append(lines: Range<Int>, of frame: PixelFrame) {
        guard !lines.isEmpty else { return }
        reserve(length + lines.count)
        guard let storage else { return }
        frame.copyLines(lines, along: axis, to: storage, at: length)
        length += lines.count
    }

    /// Appends `lines` lines of a dashed red-and-white seam marking a gap in the content.
    func appendSeam(lines: Int) {
        guard lines > 0 else { return }
        reserve(length + lines)
        guard let storage else { return }
        let red = UInt32(230) | UInt32(40) << 8 | UInt32(40) << 16 | 0xff00_0000
        let white = UInt32(0xffff_ffff)
        let rowPixels = storage.bytesPerRow / 4
        let base = storage.pixels
        let dash = max(4, lines * 3)
        for line in length..<length + lines {
            for index in 0..<breadth {
                let color = (index / dash).isMultiple(of: 2) ? red : white
                switch axis {
                case .vertical: base[line * rowPixels + index] = color
                case .horizontal: base[index * rowPixels + line] = color
                }
            }
        }
        length += lines
    }

    /// The canvas content followed by `extra` lines of `frame`, as a new image.
    func makeImage(appending extra: Range<Int>, of frame: PixelFrame) -> CGImage? {
        guard let output = makeBitmap(length: length + extra.count) else { return nil }
        if let storage {
            storage.copyLines(0..<length, along: axis, to: output, at: 0)
        }
        frame.copyLines(extra, along: axis, to: output, at: length)
        return output.context.makeImage()
    }

    /// Grows storage to hold at least `needed` lines, doubling (min 1024 lines) up to `maxLength`.
    private func reserve(_ needed: Int) {
        guard needed > capacity else { return }
        let target = min(max(needed, capacity * 2, 1024), max(needed, maxLength))
        guard let grown = makeBitmap(length: target) else { return }
        if let storage {
            storage.copyLines(0..<length, along: axis, to: grown, at: 0)
        }
        storage = grown
    }

    private func makeBitmap(length: Int) -> PixelFrame? {
        axis == .vertical
            ? PixelFrame(width: breadth, height: length, colorSpace: colorSpace)
            : PixelFrame(width: length, height: breadth, colorSpace: colorSpace)
    }
}

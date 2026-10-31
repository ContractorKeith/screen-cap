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

/// Noise-tolerant summaries of every line: luminance summed over a few bins across the line.
///
/// Live captures carry ±1 dither fixed to the screen, not the content, so once content moves no
/// line is byte-identical to where it came from and exact hashes only match by coincidence (#112).
/// Two lines are the same here when every bin agrees within `tolerance`: dither moves a bin by at
/// most two per sample, while a different glyph moves it by far more.
struct LineProfiles {
    let count: Int
    let bins: Int
    /// `count * bins` luminance sums, line-major.
    let sums: [Int32]
    /// Total luminance per line, to find match candidates quickly.
    let totals: [Int32]
    /// False when the line is flat (blank space), however it's dithered.
    let informative: [Bool]
    let tolerance: Int32

    static let maxBins = 32
    static let maxSamples = 256
    /// Luminance range a line needs to count as carrying detail.
    static let contrast = 24

    func matches(_ line: Int, _ other: LineProfiles, _ otherLine: Int) -> Bool {
        distance(line, other, otherLine) != nil
    }

    /// Summed bin differences between two lines, or nil when any bin differs beyond `tolerance`.
    func distance(_ line: Int, _ other: LineProfiles, _ otherLine: Int) -> Int32? {
        sums.withUnsafeBufferPointer { mine in
            other.sums.withUnsafeBufferPointer { theirs in
                let one = mine.baseAddress! + line * bins // swiftlint:disable:this force_unwrapping
                let two = theirs.baseAddress! + otherLine * bins // swiftlint:disable:this force_unwrapping
                var total: Int32 = 0
                for bin in 0..<bins {
                    let difference = abs(one[bin] - two[bin])
                    if difference > tolerance { return nil }
                    total += difference
                }
                return total
            }
        }
    }

    /// Hashes for two frames' lines where equal values mean "the same line, give or take noise", so
    /// `FrameAligner`'s hash-level search works on live captures. Each line joins the closest
    /// representative it matches (dithered copies of one line are all within `tolerance` of each
    /// other), so a slightly different neighbouring glyph row can't capture it.
    static func classify(_ one: LineProfiles, _ other: LineProfiles) -> ([LineHash], [LineHash]) {
        guard one.bins == other.bins else { return ([], []) }
        var representatives: [(profiles: LineProfiles, line: Int)] = []
        var buckets: [Int32: [Int]] = [:]
        let bucketSize = max(1, one.tolerance * Int32(one.bins))
        func classOf(_ profiles: LineProfiles, _ line: Int) -> Int {
            let key = profiles.totals[line] / bucketSize
            var closest: (index: Int, distance: Int32)?
            for bucket in key - 1...key + 1 {
                for index in buckets[bucket, default: []] {
                    let rep = representatives[index]
                    guard let distance = profiles.distance(line, rep.profiles, rep.line) else { continue }
                    if distance == 0 { return index }
                    if distance < closest?.distance ?? .max { closest = (index, distance) }
                }
            }
            if let closest { return closest.index }
            representatives.append((profiles, line))
            buckets[key, default: []].append(representatives.count - 1)
            return representatives.count - 1
        }
        func hashes(_ profiles: LineProfiles) -> [LineHash] {
            (0..<profiles.count).map { line in
                LineHash(value: UInt64(classOf(profiles, line)), isInformative: profiles.informative[line])
            }
        }
        let first = hashes(one)
        return (first, hashes(other))
    }
}

extension PixelFrame {
    /// Noise-tolerant line summaries along `axis` (see `LineProfiles`).
    func lineProfiles(along axis: ScrollAxis) -> LineProfiles {
        let count = length(along: axis)
        let breadth = breadth(along: axis)
        let stride = max(1, breadth / LineProfiles.maxSamples)
        let samples = (breadth + stride - 1) / stride
        let bins = max(1, min(LineProfiles.maxBins, samples))
        let perBin = (samples + bins - 1) / bins
        let rowPixels = bytesPerRow / 4
        let base = pixels
        var sums = [Int32](repeating: 0, count: count * bins)
        var totals = [Int32](repeating: 0, count: count)
        var informative = [Bool](repeating: false, count: count)
        // Unsafe buffers: this runs on every frame, and debug builds (tests) check every index.
        sums.withUnsafeMutableBufferPointer { sums in
            for line in 0..<count {
                var low = Int32.max
                var high = Int32.min
                var total: Int32 = 0
                let bin = sums.baseAddress! + line * bins // swiftlint:disable:this force_unwrapping
                for sample in 0..<samples {
                    let index = sample * stride
                    let pixel = axis == .vertical ? base[line * rowPixels + index] : base[index * rowPixels + line]
                    let value = (Int32(pixel & 0xff) + 2 * Int32((pixel >> 8) & 0xff) + Int32((pixel >> 16) & 0xff)) / 4
                    bin[sample / perBin] += value
                    total += value
                    low = min(low, value)
                    high = max(high, value)
                }
                totals[line] = total
                informative[line] = high - low > Int32(LineProfiles.contrast)
            }
        }
        return LineProfiles(count: count, bins: bins, sums: sums, totals: totals, informative: informative,
                            tolerance: Int32(2 * perBin + 4))
    }
}

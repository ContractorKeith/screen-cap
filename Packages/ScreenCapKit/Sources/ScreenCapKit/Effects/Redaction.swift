// Destructive redaction (PLAN §5.6): pixelate and blur replace pixels in a new image.
// Secure modes add seeded per-block noise so averaging or deconvolution can't recover text,
// and never use blocks smaller than a fixed share of the rect, so large text can't survive.
import CoreGraphics
import CoreImage
import Foundation

public enum Redaction {
    public enum BlurMode: Sendable {
        /// Plain Gaussian blur. Cosmetic only: OCR can read text through it.
        case smooth
        /// Two passes of randomized pixelate at a secure block size, then Gaussian blur.
        case secure
    }

    /// Max per-channel color jitter (0...255) added to each block when randomizing.
    static let colorJitter = 32
    /// Secure blocks are at least this share of the rect's shorter side. A user draws the rect
    /// around the text, so text height is bounded by it; blocks this big leave about two per glyph.
    static let secureBlockFraction = 0.4
    /// Absolute floor for secure blocks, in output pixels.
    static let minimumSecureBlock = 8

    /// The block size secure modes use for `rect` (top-left image pixels): `requested`, raised to
    /// the absolute floor and to `secureBlockFraction` of the clipped rect's shorter side.
    public static func secureBlockSize(requested: Int, rect: CGRect, imageSize: CGSize) -> Int {
        let clipped = rect.integral.intersection(CGRect(origin: .zero, size: imageSize))
        guard !clipped.isNull, !clipped.isEmpty else { return max(requested, minimumSecureBlock) }
        let shortSide = Double(min(clipped.width, clipped.height))
        let relative = Int((shortSide * secureBlockFraction).rounded(.up))
        return max(requested, minimumSecureBlock, relative)
    }

    /// Replaces `rect` (top-left image pixels) with averaged blocks of `blockSize` pixels.
    /// With `randomize` (the secure mode), the block size is raised to `secureBlockSize`, and two
    /// passes on offset grids run; each pass jitters the grid phase, each block's sampling window
    /// and each block's color from `seed`, so the output carries no exact average of the source.
    public static func pixelate(
        _ image: CGImage,
        rect: CGRect,
        blockSize: Int,
        randomize: Bool,
        seed: UInt64 = UInt64.random(in: 0...UInt64.max)
    ) throws -> CGImage {
        let bitmap = try EffectsBitmap(image: image)
        guard let region = clip(rect, to: bitmap) else { return image }
        var rng = EffectsRandom(seed: seed)
        guard randomize else {
            pixelatePass(region, block: max(1, blockSize), randomize: false, in: bitmap, rng: &rng)
            return try bitmap.makeImage()
        }
        let size = CGSize(width: bitmap.width, height: bitmap.height)
        let block = secureBlockSize(requested: blockSize, rect: rect, imageSize: size)
        pixelatePass(region, block: block, randomize: true, in: bitmap, rng: &rng)
        pixelatePass(region, block: block, randomize: true, in: bitmap, rng: &rng)
        return try bitmap.makeImage()
    }

    /// One pixelate pass over `region`, in place.
    private static func pixelatePass(
        _ region: PixelRect, block: Int, randomize: Bool, in bitmap: EffectsBitmap, rng: inout EffectsRandom
    ) {
        let phaseX = randomize ? rng.int(in: 0...(block - 1)) : 0
        let phaseY = randomize ? rng.int(in: 0...(block - 1)) : 0

        var blockY = region.minY - phaseY
        while blockY < region.maxY {
            var blockX = region.minX - phaseX
            while blockX < region.maxX {
                let cell = PixelRect(minX: blockX, minY: blockY, maxX: blockX + block, maxY: blockY + block)
                    .intersection(region)
                var sample = cell
                if randomize {
                    let shifted = cell.offsetBy(
                        dx: rng.int(in: -block / 2...block / 2), dy: rng.int(in: -block / 2...block / 2)
                    ).intersection(region)
                    if !shifted.isEmpty { sample = shifted }
                }
                var color = average(of: sample, in: bitmap)
                if randomize { color = jitter(color, using: &rng) }
                fill(cell, with: color, in: bitmap)
                blockX += block
            }
            blockY += block
        }
    }

    /// Blurs `rect` (top-left image pixels). The blur samples only pixels inside `rect`.
    public static func blur(
        _ image: CGImage,
        rect: CGRect,
        radius: CGFloat,
        mode: BlurMode,
        seed: UInt64 = UInt64.random(in: 0...UInt64.max)
    ) throws -> CGImage {
        guard mode == .secure else { return try gaussianBlur(image, rect: rect, radius: radius) }
        let size = CGSize(width: image.width, height: image.height)
        let block = secureBlockSize(requested: Int(radius.rounded()), rect: rect, imageSize: size)
        let pixelated = try pixelate(image, rect: rect, blockSize: block, randomize: true, seed: seed)
        // Soften the block edges so it reads as a blur; the blocks already hold no glyph detail.
        return try gaussianBlur(pixelated, rect: rect, radius: max(radius, CGFloat(block) / 4))
    }

    // MARK: - Helpers

    private static func gaussianBlur(_ image: CGImage, rect: CGRect, radius: CGFloat) throws -> CGImage {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clipped = rect.integral.intersection(bounds)
        guard !clipped.isEmpty, radius > 0 else { return image }
        // Core Image is bottom-left origin.
        let region = CGRect(
            x: clipped.minX, y: bounds.height - clipped.maxY, width: clipped.width, height: clipped.height
        )
        let input = CIImage(cgImage: image)
        let blurred = input.cropped(to: region)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(radius))
            .cropped(to: region)
        // Software renderer: the GPU path hangs on headless VMs (CI) and a small rect is cheap on CPU.
        let context = CIContext(options: [
            .workingColorSpace: EffectsBitmap.colorSpace,
            .useSoftwareRenderer: true
        ])
        guard let rendered = context.createCGImage(blurred, from: region) else {
            throw EffectsError.imageCreationFailed
        }
        let bitmap = try EffectsBitmap(image: image)
        bitmap.context.setBlendMode(.copy)
        bitmap.context.draw(rendered, in: bitmap.cgRect(clipped))
        return try bitmap.makeImage()
    }

    private static func clip(_ rect: CGRect, to bitmap: EffectsBitmap) -> PixelRect? {
        let bounds = CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height)
        let clipped = rect.integral.intersection(bounds)
        guard !clipped.isNull, !clipped.isEmpty else { return nil }
        return PixelRect(
            minX: Int(clipped.minX), minY: Int(clipped.minY), maxX: Int(clipped.maxX), maxY: Int(clipped.maxY)
        )
    }

    private static func average(of rect: PixelRect, in bitmap: EffectsBitmap) -> [Int] {
        var sums = [0, 0, 0, 0]
        let pixels = bitmap.pixels
        for row in rect.minY..<rect.maxY {
            for column in rect.minX..<rect.maxX {
                let index = bitmap.offset(x: column, y: row)
                for channel in 0..<4 { sums[channel] += Int(pixels[index + channel]) }
            }
        }
        let count = max(1, rect.area)
        return sums.map { ($0 + count / 2) / count }
    }

    /// Adds per-channel noise, keeping premultiplied color channels within alpha.
    private static func jitter(_ color: [Int], using rng: inout EffectsRandom) -> [Int] {
        let alpha = color[3]
        return (0..<3).map { channel in
            min(alpha, max(0, color[channel] + rng.int(in: -colorJitter...colorJitter)))
        } + [alpha]
    }

    private static func fill(_ rect: PixelRect, with color: [Int], in bitmap: EffectsBitmap) {
        let pixels = bitmap.pixels
        for row in rect.minY..<rect.maxY {
            for column in rect.minX..<rect.maxX {
                let index = bitmap.offset(x: column, y: row)
                for channel in 0..<4 { pixels[index + channel] = UInt8(color[channel]) }
            }
        }
    }
}

/// Integer pixel rect, half-open on max edges.
struct PixelRect: Equatable {
    var minX: Int
    var minY: Int
    var maxX: Int
    var maxY: Int

    var isEmpty: Bool { maxX <= minX || maxY <= minY }
    var area: Int { isEmpty ? 0 : (maxX - minX) * (maxY - minY) }

    func intersection(_ other: PixelRect) -> PixelRect {
        PixelRect(
            minX: max(minX, other.minX), minY: max(minY, other.minY),
            maxX: min(maxX, other.maxX), maxY: min(maxY, other.maxY)
        )
    }

    func offsetBy(dx: Int, dy: Int) -> PixelRect {
        PixelRect(minX: minX + dx, minY: minY + dy, maxX: maxX + dx, maxY: maxY + dy)
    }
}

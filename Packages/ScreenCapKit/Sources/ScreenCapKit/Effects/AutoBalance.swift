// Background Auto Balance (PLAN §5.5): padding that visually centers a screenshot's content.
import CoreGraphics

public enum AutoBalance {
    /// Content bounding box in top-left image pixels, or nil if the image is all background.
    ///
    /// If the dominant border color is mostly transparent, content is any pixel with alpha at least
    /// `alphaThreshold` (the default skips soft, semi-transparent window shadows). Otherwise content
    /// is any pixel differing from the dominant border color by more than `tolerance` (0...255) in
    /// some channel.
    public static func contentBounds(
        in image: CGImage, alphaThreshold: Double = 0.75, tolerance: Int = 16
    ) throws -> CGRect? {
        let bitmap = try EffectsBitmap(image: image)
        let background = dominantBorderColor(in: bitmap)
        let pixels = bitmap.pixels
        let minAlpha = Int((alphaThreshold * 255).rounded())
        let transparent = background[3] < 128

        func isContent(_ index: Int) -> Bool {
            if transparent { return Int(pixels[index + 3]) >= minAlpha }
            return (0..<4).contains { abs(Int(pixels[index + $0]) - background[$0]) > tolerance }
        }

        var bounds = PixelRect(minX: bitmap.width, minY: bitmap.height, maxX: 0, maxY: 0)
        for row in 0..<bitmap.height {
            for column in 0..<bitmap.width where isContent(bitmap.offset(x: column, y: row)) {
                bounds.minX = min(bounds.minX, column)
                bounds.maxX = max(bounds.maxX, column + 1)
                bounds.minY = min(bounds.minY, row)
                bounds.maxY = max(bounds.maxY, row + 1)
            }
        }
        guard !bounds.isEmpty else { return nil }
        return CGRect(
            x: bounds.minX, y: bounds.minY, width: bounds.maxX - bounds.minX, height: bounds.maxY - bounds.minY
        )
    }

    /// Per-edge padding that, added around `image`, centers its content on the canvas.
    ///
    /// Every edge gets at least `minimum` of total space around the content. When the final
    /// composite shows a `shadow` (baked into a window capture or added by the compositor), the
    /// content shifts against the shadow offset by half of it, since the shadow pulls visual
    /// weight its way (usually down).
    public static func padding(
        for image: CGImage, shadow: EffectsShadow? = nil, minimum: CGFloat = 48
    ) throws -> EffectsInsets {
        let size = CGSize(width: image.width, height: image.height)
        let content = try contentBounds(in: image) ?? CGRect(origin: .zero, size: size)
        let margins = EffectsInsets(
            top: content.minY, left: content.minX,
            bottom: size.height - content.maxY, right: size.width - content.maxX
        )
        let shift = CGPoint(x: (shadow?.offset.width ?? 0) / 2, y: (shadow?.offset.height ?? 0) / 2)

        // Total space each side should have: equal on both sides of an axis, minus/plus the shift.
        let horizontal = max(minimum + abs(shift.x), margins.left + shift.x, margins.right - shift.x)
        let vertical = max(minimum + abs(shift.y), margins.top + shift.y, margins.bottom - shift.y)
        return EffectsInsets(
            top: (vertical - shift.y - margins.top).rounded(),
            left: (horizontal - shift.x - margins.left).rounded(),
            bottom: (vertical + shift.y - margins.bottom).rounded(),
            right: (horizontal + shift.x - margins.right).rounded()
        )
    }

    /// Most common border color (RGBA, premultiplied bytes), quantized to absorb noise.
    static func dominantBorderColor(in bitmap: EffectsBitmap) -> [Int] {
        var counts: [UInt32: (count: Int, index: Int)] = [:]
        let pixels = bitmap.pixels
        func visit(_ column: Int, _ row: Int) {
            let index = bitmap.offset(x: column, y: row)
            let key = (0..<4).reduce(UInt32(0)) { ($0 << 8) | UInt32(pixels[index + $1] >> 3) }
            counts[key, default: (0, index)].count += 1
        }
        for column in 0..<bitmap.width {
            visit(column, 0)
            visit(column, bitmap.height - 1)
        }
        for row in 0..<bitmap.height {
            visit(0, row)
            visit(bitmap.width - 1, row)
        }
        let index = counts.values.max { $0.count < $1.count }?.index ?? 0
        return (0..<4).map { Int(pixels[index + $0]) }
    }
}

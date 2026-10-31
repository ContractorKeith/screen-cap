// Spotlight: dims everything outside the union of one or more shapes.
import CoreGraphics

public enum Spotlight {
    /// Returns a copy of `image` with a `dimColor` overlay at `dimOpacity` outside all `shapes`
    /// (top-left image pixels). Pixels inside any shape are left unchanged.
    public static func apply(
        _ image: CGImage,
        shapes: [EffectsShape],
        dimColor: EffectsColor = .black,
        dimOpacity: Double = 0.5
    ) throws -> CGImage {
        let bitmap = try EffectsBitmap(image: image)
        let full = CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height)

        // Build the dim layer, then punch out every shape. Clearing per shape gives a true union,
        // which an even-odd fill would not when shapes overlap.
        let overlay = try EffectsBitmap(width: bitmap.width, height: bitmap.height)
        var color = dimColor
        color.alpha = min(1, max(0, dimOpacity)) * dimColor.alpha
        overlay.context.setFillColor(color.cgColor)
        overlay.context.fill(full)
        overlay.context.setBlendMode(.clear)
        for shape in shapes {
            overlay.context.addPath(shape.cgPath(in: overlay))
            overlay.context.fillPath()
        }

        bitmap.context.draw(try overlay.makeImage(), in: full)
        return try bitmap.makeImage()
    }
}

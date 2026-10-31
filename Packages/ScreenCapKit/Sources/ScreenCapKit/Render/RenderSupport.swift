import CoreGraphics
import Foundation

/// Options for one render pass.
public struct RenderOptions: Sendable, Equatable {
    /// Output pixels per document pixel; 1 or 2 in practice. Output size is the canvas times this.
    public var scale: Double
    /// Draw `document.background` (fill, padding, rounded corners, shadow) around the base image.
    /// When false, or the document has no background, the output is the base image's size.
    public var includeBackground: Bool

    public init(scale: Double = 1, includeBackground: Bool = true) {
        self.scale = scale
        self.includeBackground = includeBackground
    }
}

public enum RenderError: Error, Equatable {
    case invalidScale(Double)
    case contextCreationFailed
}

/// Applies the pixel effects (blur, pixelate, spotlight) the renderer can't draw as vectors.
///
/// The renderer snapshots everything drawn so far and passes it in with the annotation's
/// geometry already mapped to that snapshot's pixels (top-left origin, render scale and
/// background offset applied). Lengths that aren't points (blur radius, block size) are not
/// scaled; multiply by `scale` if they should be. Return nil to leave the canvas untouched.
public protocol RedactionRenderer: Sendable {
    func apply(_ kind: Annotation.Kind, to canvas: CGImage, scale: Double) -> CGImage?
}

/// Stub hook that leaves blur, pixelate and spotlight undrawn. Tests use it to isolate vector
/// drawing; the renderer's default is `EffectsRedactionRenderer`.
public struct NoOpRedactionRenderer: RedactionRenderer {
    public init() {}

    public func apply(_ kind: Annotation.Kind, to canvas: CGImage, scale: Double) -> CGImage? { nil }
}

extension RGBAColor {
    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    /// Black or white, whichever reads better on top of this color.
    var contrasting: RGBAColor {
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.6 ? .black : .white
    }
}

extension CGContext {
    /// Draws `image` upright into `rect` when the CTM is flipped to a top-left origin.
    func drawUpright(_ image: CGImage, in rect: CGRect) {
        saveGState()
        translateBy(x: 0, y: rect.minY + rect.maxY)
        scaleBy(x: 1, y: -1)
        draw(image, in: rect)
        restoreGState()
    }
}

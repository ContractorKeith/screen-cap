import CoreGraphics
import Foundation

/// Default redaction hook: applies the destructive Effects pixelate, blur and spotlight (PLAN §5.6).
///
/// Blur radius and block size are document pixels, so they are multiplied by the render scale to
/// look the same at 1x and 2x. `seed` drives the secure-mode noise; one renderer gives identical
/// output on every redraw, so the editor canvas doesn't shimmer while you work.
public struct EffectsRedactionRenderer: RedactionRenderer {
    public var seed: UInt64

    public init(seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        self.seed = seed
    }

    public func apply(_ kind: Annotation.Kind, to canvas: CGImage, scale: Double) -> CGImage? {
        switch kind {
        case let .blur(rect, mode, radius):
            return redact(rect, in: canvas) {
                try Redaction.blur(canvas, rect: rect, radius: radius * scale, mode: Redaction.BlurMode(mode),
                                   seed: seed)
            }
        case let .pixelate(rect, blockSize, randomize):
            let block = max(1, Int((Double(blockSize) * scale).rounded()))
            return redact(rect, in: canvas) {
                try Redaction.pixelate(canvas, rect: rect, blockSize: block, randomize: randomize, seed: seed)
            }
        case let .spotlight(shapes):
            return try? Spotlight.apply(canvas, shapes: shapes)
        default:
            return nil
        }
    }

    /// Runs `effect`; if it fails, blacks out `rect` rather than leave the secret readable.
    private func redact(_ rect: CGRect, in canvas: CGImage, _ effect: () throws -> CGImage) -> CGImage? {
        if let result = try? effect() { return result }
        guard let bitmap = try? EffectsBitmap(image: canvas) else { return nil }
        bitmap.context.setFillColor(RGBAColor.black.cgColor)
        bitmap.context.fill(bitmap.cgRect(rect))
        return try? bitmap.makeImage()
    }
}

extension Redaction.BlurMode {
    /// The Effects mode for a document blur annotation's mode.
    init(_ mode: Annotation.BlurMode) {
        switch mode {
        case .secure: self = .secure
        case .smooth: self = .smooth
        }
    }
}

import CoreGraphics
import Foundation

// Opaque shapes as redactions (#74): which objects hide what's under them, and which the editor
// treats as redactions by default.

extension Annotation {
    /// Kinds that paint a filled area and so can serve as a redaction bar: rectangles, ellipses,
    /// highlights and the two background text presets. The inspector shows "Use as redaction" for these.
    public var canBeRedaction: Bool {
        switch kind {
        case .rectangle, .ellipse, .highlight: true
        case let .text(_, preset, _, _): Self.backgroundPresets.contains(preset)
        default: false
        }
    }

    /// True when the object paints a fully opaque fill over `coverRect`, so the pixels beneath
    /// can't be seen in the render (but would still be in an unbaked project file).
    public var isOpaqueCover: Bool {
        guard style.opacity >= Self.opaque else { return false }
        switch kind {
        case let .rectangle(_, filled, _):
            let fill = filled ? (style.fillColor ?? style.strokeColor) : style.fillColor
            return (fill?.alpha ?? 0) >= Self.opaque
        case .ellipse:
            return (style.fillColor?.alpha ?? 0) >= Self.opaque
        case let .highlight(_, color):
            // Highlights multiply, so only black hides what's below.
            return color.alpha >= Self.opaque && max(color.red, color.green, color.blue) <= 0.01
        case let .text(_, preset, _, _):
            let background = style.fillColor ?? style.strokeColor
            return Self.backgroundPresets.contains(preset) && background.alpha >= Self.opaque
        default:
            return false
        }
    }

    /// The area the object's fill covers, in image pixels. Null for kinds that can't cover.
    public var coverRect: CGRect {
        switch kind {
        case let .rectangle(rect, _, _), let .ellipse(rect), let .text(_, _, _, rect):
            return rect.standardized
        case let .highlight(.rect(rect), _):
            return rect.standardized
        case .highlight(.path, _):
            let half = style.strokeWidth / 2
            return kind.bounds.insetBy(dx: -half, dy: -half)
        default:
            return .null
        }
    }

    /// The redaction flag with nil resolved: on for an opaque cover over detected text.
    public func resolvedRedaction(textLines: [CGRect]) -> Bool {
        if let redaction { return redaction }
        return isOpaqueCover && RedactionCoverage.coversText(coverRect, lines: textLines)
    }

    private static let opaque = 0.999
    private static let backgroundPresets: Set<Int> = [TextPreset.filledBackground.rawValue,
                                                      TextPreset.roundedLabel.rawValue]
}

/// Decides whether a shape sits over text, from Vision's text-line boxes.
public enum RedactionCoverage {
    /// True if the shape hides most of some line, or most of the shape is over text lines
    /// (a bar drawn over one word of a long line).
    public static func coversText(_ shape: CGRect, lines: [CGRect]) -> Bool {
        let shapeArea = area(shape)
        guard shapeArea > 0 else { return false }
        var overText = 0.0
        for line in lines {
            let overlap = area(shape.intersection(line))
            if overlap >= area(line) * 0.5, overlap > 0 { return true }
            overText += overlap
        }
        return overText >= shapeArea * 0.4
    }

    private static func area(_ rect: CGRect) -> Double {
        rect.isNull || rect.isEmpty ? 0 : Double(rect.width * rect.height)
    }
}

extension Document {
    /// Opaque shapes left on automatic (`redaction == nil`) that don't resolve to a redaction:
    /// they hide pixels in the render, but the project file would still hold them.
    public func unmarkedOpaqueCovers(textLines: [CGRect]) -> [Annotation] {
        drawOrder.filter { $0.redaction == nil && $0.isOpaqueCover && !$0.resolvedRedaction(textLines: textLines) }
    }

    /// A copy with every automatic flag that resolves to on set to `true`, for saving.
    public func resolvingRedactions(textLines: [CGRect]) -> Document {
        var copy = self
        for index in copy.annotations.indices where copy.annotations[index].redaction == nil
            && copy.annotations[index].resolvedRedaction(textLines: textLines) {
            copy.annotations[index].redaction = true
        }
        return copy
    }
}

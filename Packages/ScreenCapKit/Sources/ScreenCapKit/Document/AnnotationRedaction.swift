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

    /// True when the object paints a fill over `coverRect` that hides what's beneath, so it
    /// reads as a redaction bar. Near-opaque counts (#99): at 90% or more, a levels stretch
    /// brings the text back, so these get the same treatment as fully opaque covers.
    public var isOpaqueCover: Bool {
        let opacity = min(max(style.opacity, 0), 1)
        func covers(_ color: RGBAColor?) -> Bool { opacity * (color?.alpha ?? 0) >= Self.nearOpaque }
        switch kind {
        case let .rectangle(_, filled, _):
            return covers(filled ? (style.fillColor ?? style.strokeColor) : style.fillColor)
        case .ellipse:
            return covers(style.fillColor)
        case let .highlight(_, color):
            // Highlights multiply, so only a dark color hides what's below.
            return covers(color) && max(color.red, color.green, color.blue) <= Self.darkHighlight
        case let .text(_, preset, _, _):
            return Self.backgroundPresets.contains(preset) && covers(style.fillColor ?? style.strokeColor)
        default:
            return false
        }
    }

    /// How a shape used as a redaction is drawn: fully opaque, with highlights painted as a solid
    /// fill rather than multiplied, so nothing beneath survives a curves or levels adjustment (#99).
    /// Other objects come back unchanged.
    public var solidCover: Annotation {
        guard redaction == true, canBeRedaction else { return self }
        var copy = self
        copy.style.opacity = 1
        copy.style.strokeColor.alpha = 1
        copy.style.fillColor?.alpha = 1
        if case let .highlight(region, color) = kind {
            var solid = color
            solid.alpha = 1
            copy.style.shadow = nil
            switch region {
            case let .rect(rect):
                copy.style.fillColor = solid
                copy.kind = .rectangle(rect: rect, filled: true, cornerRadius: 0)
            case let .path(points):
                copy.style.strokeColor = solid
                copy.kind = .path(points: points, smoothed: false)
            }
        }
        return copy
    }

    /// True if the object hides what's beneath once used as a redaction (it has a fill).
    public var coversAsRedaction: Bool {
        var marked = self
        marked.redaction = true
        return marked.solidCover.isOpaqueCover
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

    private static let nearOpaque = 0.9
    private static let darkHighlight = 0.2
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

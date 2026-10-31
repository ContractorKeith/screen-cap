import AppKit
import CoreGraphics
import CoreText
import Foundation

/// The seven text styles stored as `Annotation.Kind.text(preset:)`, 1...7.
public enum TextPreset: Int, Sendable, CaseIterable {
    case plain = 1
    case outlined
    case filledBackground
    case monospace
    case roundedLabel
    case boldUppercase
    case handwritten
}

/// Text and counters, laid out with CoreText.
enum TextPainter {
    /// A text annotation's content and frame.
    struct Box {
        var string: String
        var preset: TextPreset
        var fontSize: Double
        var rect: CGRect
    }

    /// Draws the box's string wrapped inside its rect. Text color is the stroke color, except on the two
    /// background presets, where the background takes the fill (or stroke) color and the text
    /// is black or white for contrast. Lines that don't fit the rect are dropped.
    static func draw(_ box: Box, style: Annotation.Style, in context: CGContext) {
        let (string, preset, fontSize, rect) = (box.string, box.preset, box.fontSize, box.rect)
        guard fontSize > 0, rect.width > 0, rect.height > 0 else { return }
        let font = font(for: preset, size: fontSize)
        let text = preset == .boldUppercase ? string.uppercased() : string
        var textColor = style.strokeColor
        var textRect = rect

        switch preset {
        case .filledBackground, .roundedLabel:
            let background = style.fillColor ?? style.strokeColor
            let radius = preset == .roundedLabel ? min(rect.height / 2, fontSize * 0.6) : fontSize * 0.15
            let clamped = min(radius, rect.width / 2, rect.height / 2)
            AnnotationPainter.fill(CGPath(roundedRect: rect, cornerWidth: clamped, cornerHeight: clamped,
                                          transform: nil), color: background, in: context)
            textColor = background.contrasting
            textRect = rect.insetBy(dx: min(fontSize * 0.4, rect.width / 4), dy: min(fontSize * 0.2, rect.height / 4))
        case .outlined:
            // Outline pass first, so the fill pass sits on top of the inner half of the stroke.
            let outline = style.fillColor ?? style.strokeColor.contrasting
            let attributes: [NSAttributedString.Key: Any] = [
                .init(kCTFontAttributeName as String): font,
                .init(kCTStrokeColorAttributeName as String): outline.cgColor,
                .init(kCTStrokeWidthAttributeName as String): 24 // percent of font size
            ]
            context.setLineJoin(.round)
            drawFrame(NSAttributedString(string: text, attributes: attributes), in: textRect, context: context)
        case .plain, .monospace, .boldUppercase, .handwritten:
            break
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .init(kCTFontAttributeName as String): font,
            .init(kCTForegroundColorAttributeName as String): textColor.cgColor
        ]
        drawFrame(NSAttributedString(string: text, attributes: attributes), in: textRect, context: context)
    }

    /// Filled circle with its number centered, in black or white for contrast.
    static func drawCounter(_ number: Int, center: CGPoint, radius: Double, fill: RGBAColor, in context: CGContext) {
        guard radius > 0 else { return }
        let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        AnnotationPainter.fill(CGPath(ellipseIn: circle, transform: nil), color: fill, in: context)

        let label = String(number)
        let size = radius * (label.count > 1 ? 1.5 / Double(label.count) + 0.2 : 1.15)
        let attributes: [NSAttributedString.Key: Any] = [
            .init(kCTFontAttributeName as String): NSFont.systemFont(ofSize: size, weight: .bold) as CTFont,
            .init(kCTForegroundColorAttributeName as String): fill.contrasting.cgColor
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: 1, y: -1) // CoreText draws y-up.
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    static func font(for preset: TextPreset, size: Double) -> CTFont {
        let font: NSFont
        switch preset {
        case .plain, .outlined, .filledBackground:
            font = .systemFont(ofSize: size, weight: .semibold)
        case .monospace:
            font = .monospacedSystemFont(ofSize: size, weight: .regular)
        case .roundedLabel:
            let base = NSFont.systemFont(ofSize: size, weight: .semibold)
            font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        case .boldUppercase:
            font = .systemFont(ofSize: size, weight: .heavy)
        case .handwritten:
            font = NSFont(name: "Noteworthy-Bold", size: size)
                ?? NSFont(name: "MarkerFelt-Wide", size: size)
                ?? .systemFont(ofSize: size)
        }
        return font as CTFont
    }

    /// Lays out and draws `text` top-down inside `rect` (model space, y down).
    private static func drawFrame(_ text: NSAttributedString, in rect: CGRect, context: CGContext) {
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(rect: CGRect(origin: .zero, size: rect.size), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1) // CoreText draws y-up.
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}

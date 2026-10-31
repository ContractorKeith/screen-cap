import CoreGraphics
import Foundation

/// Draws one vector annotation into a context whose CTM maps image pixels, top-left origin.
enum AnnotationPainter {
    static func draw(_ annotation: Annotation, layers: [String: CGImage], scale: Double, in context: CGContext) {
        let style = annotation.style
        context.saveGState()
        defer { context.restoreGState() }
        context.setAlpha(min(max(style.opacity, 0), 1))

        // Highlights multiply onto what's below; a transparency layer would composite normally.
        if case let .highlight(region, color) = annotation.kind {
            context.setBlendMode(.multiply)
            drawHighlight(region, color: color, width: style.strokeWidth, in: context)
            return
        }

        if let shadow = style.shadow { setShadow(shadow, scale: scale, in: context) }
        // One layer per annotation so opacity and shadow apply to the shape as a whole
        // (an arrow's shaft and head don't double up where they overlap).
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        drawShape(annotation.kind, style: style, layers: layers, in: context)
        context.endTransparencyLayer()
    }

    /// Shadow offsets live in the context's base space, which is unflipped and unscaled.
    static func setShadow(_ shadow: Document.Shadow, scale: Double, in context: CGContext) {
        context.setShadow(offset: CGSize(width: shadow.offset.width * scale, height: -shadow.offset.height * scale),
                          blur: shadow.radius * scale, color: shadow.color.cgColor)
    }

    private static func drawShape(_ kind: Annotation.Kind, style: Annotation.Style,
                                  layers: [String: CGImage], in context: CGContext) {
        switch kind {
        case let .arrow(start, end, arrowStyle):
            ArrowPainter.draw(start: start, end: end, style: arrowStyle,
                              pen: .init(color: style.strokeColor, width: style.strokeWidth), in: context)
        case let .rectangle(rect, filled, cornerRadius):
            drawRectangle(rect.standardized, filled: filled, cornerRadius: cornerRadius, style: style, in: context)
        case let .ellipse(rect):
            fillAndStroke(CGPath(ellipseIn: rect.standardized, transform: nil), style: style, in: context)
        case let .line(start, end):
            let path = CGMutablePath()
            path.move(to: start)
            path.addLine(to: end)
            stroke(path, color: style.strokeColor, width: style.strokeWidth, in: context)
        case let .text(string, preset, fontSize, rect):
            let box = TextPainter.Box(string: string, preset: TextPreset(rawValue: preset) ?? .plain,
                                      fontSize: fontSize, rect: rect.standardized)
            TextPainter.draw(box, style: style, in: context)
        case let .counter(number, center, radius):
            TextPainter.drawCounter(number, center: center, radius: radius,
                                    fill: style.fillColor ?? style.strokeColor, in: context)
        case let .path(points, smoothed):
            drawPath(smoothed ? PathSmoothing.catmullRom(points: points) : points, style: style, in: context)
        case let .imageLayer(layerName, rect):
            if let image = layers[layerName] { context.drawUpright(image, in: rect.standardized) }
        case .highlight, .blur, .pixelate, .spotlight:
            break // Drawn by the caller.
        }
    }

    private static func drawRectangle(_ rect: CGRect, filled: Bool, cornerRadius: Double,
                                      style: Annotation.Style, in context: CGContext) {
        let radius = min(max(cornerRadius, 0), rect.width / 2, rect.height / 2)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if filled {
            fill(path, color: style.fillColor ?? style.strokeColor, in: context)
        } else {
            fillAndStroke(path, style: style, in: context)
        }
    }

    private static func drawPath(_ points: [CGPoint], style: Annotation.Style, in context: CGContext) {
        guard let first = points.first else { return }
        if points.count == 1 {
            let radius = style.strokeWidth / 2
            let dot = CGRect(x: first.x - radius, y: first.y - radius, width: radius * 2, height: radius * 2)
            fill(CGPath(ellipseIn: dot, transform: nil), color: style.strokeColor, in: context)
            return
        }
        let path = CGMutablePath()
        path.addLines(between: points)
        stroke(path, color: style.strokeColor, width: style.strokeWidth, in: context)
    }

    private static func drawHighlight(_ region: Annotation.HighlightRegion, color: RGBAColor, width: Double,
                                      in context: CGContext) {
        switch region {
        case let .rect(rect):
            context.setFillColor(color.cgColor)
            context.fill(rect.standardized)
        case let .path(points):
            guard points.count > 1 else { return }
            let path = CGMutablePath()
            path.addLines(between: points)
            context.addPath(path)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width)
            context.setLineCap(.butt)
            context.setLineJoin(.round)
            context.strokePath()
        }
    }

    // MARK: - Primitives

    static func fill(_ path: CGPath, color: RGBAColor, in context: CGContext) {
        context.addPath(path)
        context.setFillColor(color.cgColor)
        context.fillPath()
    }

    static func stroke(_ path: CGPath, color: RGBAColor, width: Double, in context: CGContext) {
        context.addPath(path)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }

    /// Optional fill, then the outline.
    private static func fillAndStroke(_ path: CGPath, style: Annotation.Style, in context: CGContext) {
        if let fillColor = style.fillColor { fill(path, color: fillColor, in: context) }
        if style.strokeWidth > 0 { stroke(path, color: style.strokeColor, width: style.strokeWidth, in: context) }
    }
}

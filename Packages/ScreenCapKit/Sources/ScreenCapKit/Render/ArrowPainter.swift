import CoreGraphics
import Foundation

/// The four arrow styles. Heads scale with stroke width; the shaft stops inside the head so
/// its cap never pokes past the point.
enum ArrowPainter {
    /// Head length and full base width for a given stroke width and arrow length.
    static func headSize(strokeWidth: Double, arrowLength: Double) -> (length: Double, width: Double) {
        let length = min(max(10, strokeWidth * 4), arrowLength * 0.6)
        return (length, length * 0.9)
    }

    /// How far the shaft runs into the head, as a fraction of head length back from the tip.
    private static let shaftInset = 0.8

    /// Stroke color and width for one arrow.
    struct Pen {
        var color: RGBAColor
        var width: Double
    }

    static func draw(start: CGPoint, end: CGPoint, style: Annotation.ArrowStyle, pen: Pen, in context: CGContext) {
        let color = pen.color
        let width = pen.width
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 0 else { return }
        let head = headSize(strokeWidth: width, arrowLength: length)
        let unit = CGVector(dx: (end.x - start.x) / length, dy: (end.y - start.y) / length)

        switch style {
        case .straight:
            strokeShaft(from: start, to: offset(end, unit, -head.length * shaftInset),
                        color: color, width: width, in: context)
            fillHead(tip: end, direction: unit, size: head, color: color, in: context)
        case .doubleHeaded:
            let back = CGVector(dx: -unit.dx, dy: -unit.dy)
            strokeShaft(from: offset(start, unit, head.length * shaftInset),
                        to: offset(end, unit, -head.length * shaftInset), color: color, width: width, in: context)
            fillHead(tip: end, direction: unit, size: head, color: color, in: context)
            fillHead(tip: start, direction: back, size: head, color: color, in: context)
        case .tapered:
            // Thick tapered: wider head, shaft grows from a thin tail to a wide base.
            let wide = (length: head.length * 1.2, width: max(head.width * 1.3, width * 3))
            let base = offset(end, unit, -wide.length * shaftInset)
            let normal = CGVector(dx: -unit.dy, dy: unit.dx)
            let tail = width * 0.25
            let neck = width * 0.9
            let shaft = CGMutablePath()
            shaft.addLines(between: [
                offset(start, normal, tail), offset(base, normal, neck),
                offset(base, normal, -neck), offset(start, normal, -tail)
            ])
            shaft.closeSubpath()
            AnnotationPainter.fill(shaft, color: color, in: context)
            fillHead(tip: end, direction: unit, size: wide, color: color, in: context)
        case let .curved(control):
            drawCurved(start: start, control: control, end: end, pen: pen, in: context)
        }
    }

    /// Quadratic curve through `control`; the head follows the tangent at the end.
    private static func drawCurved(start: CGPoint, control: CGPoint, end: CGPoint, pen: Pen,
                                   in context: CGContext) {
        let head = headSize(strokeWidth: pen.width, arrowLength: hypot(end.x - start.x, end.y - start.y))
        var tangent = CGVector(dx: end.x - control.x, dy: end.y - control.y)
        if hypot(tangent.dx, tangent.dy) < 0.001 { tangent = CGVector(dx: end.x - start.x, dy: end.y - start.y) }
        let tangentLength = hypot(tangent.dx, tangent.dy)
        let unit = CGVector(dx: tangent.dx / tangentLength, dy: tangent.dy / tangentLength)

        // Cut the curve where it is shaftInset * head length from the tip (bisection on t),
        // then keep the first piece via de Casteljau so the shape is unchanged.
        let target = head.length * shaftInset
        var low = 0.0
        var high = 1.0
        for _ in 0..<24 {
            let mid = (low + high) / 2
            let point = quadPoint(start, control, end, t: mid)
            if hypot(end.x - point.x, end.y - point.y) > target { low = mid } else { high = mid }
        }
        let cut = low
        let shaftControl = lerp(start, control, cut)
        let shaftEnd = quadPoint(start, control, end, t: cut)

        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(to: shaftEnd, control: shaftControl)
        AnnotationPainter.stroke(path, color: pen.color, width: pen.width, in: context)
        fillHead(tip: end, direction: unit, size: head, color: pen.color, in: context)
    }

    private static func strokeShaft(from start: CGPoint, to end: CGPoint, color: RGBAColor, width: Double,
                                    in context: CGContext) {
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)
        AnnotationPainter.stroke(path, color: color, width: width, in: context)
    }

    private static func fillHead(tip: CGPoint, direction: CGVector, size: (length: Double, width: Double),
                                 color: RGBAColor, in context: CGContext) {
        let base = offset(tip, direction, -size.length)
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        let path = CGMutablePath()
        path.addLines(between: [tip, offset(base, normal, size.width / 2), offset(base, normal, -size.width / 2)])
        path.closeSubpath()
        AnnotationPainter.fill(path, color: color, in: context)
    }

    // MARK: - Geometry

    private static func offset(_ point: CGPoint, _ vector: CGVector, _ distance: Double) -> CGPoint {
        CGPoint(x: point.x + vector.dx * distance, y: point.y + vector.dy * distance)
    }

    private static func lerp(_ from: CGPoint, _ target: CGPoint, _ fraction: Double) -> CGPoint {
        CGPoint(x: from.x + (target.x - from.x) * fraction, y: from.y + (target.y - from.y) * fraction)
    }

    private static func quadPoint(_ start: CGPoint, _ control: CGPoint, _ end: CGPoint, t fraction: Double) -> CGPoint {
        lerp(lerp(start, control, fraction), lerp(control, end, fraction), fraction)
    }
}

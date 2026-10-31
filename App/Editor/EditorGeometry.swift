import CoreGraphics
import Foundation
import ScreenCapKit

// Pure hit-testing and handle math for the canvas. Everything is in image pixels.

/// A selection handle: eight around a box, or the endpoints / control point of a line or arrow.
enum Handle: Hashable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    case start, end, control

    static let boxHandles: [Handle] = [.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left]

    /// Position of a box handle on `rect`.
    func point(on rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        case .start, .end, .control: CGPoint(x: rect.midX, y: rect.midY)
        }
    }

    var isCorner: Bool { [.topLeft, .topRight, .bottomRight, .bottomLeft].contains(self) }
}

enum EditorGeometry {
    // MARK: - Handles

    /// Handles shown for a selected annotation, with their positions.
    static func handles(for kind: Annotation.Kind) -> [(handle: Handle, point: CGPoint)] {
        switch kind {
        case let .arrow(start, end, style):
            var result: [(handle: Handle, point: CGPoint)] = [(.start, start), (.end, end)]
            if case let .curved(control) = style { result.append((.control, control)) }
            return result
        case let .line(start, end):
            return [(.start, start), (.end, end)]
        default:
            let bounds = kind.bounds
            guard !bounds.isNull else { return [] }
            return Handle.boxHandles.map { ($0, $0.point(on: bounds)) }
        }
    }

    /// The handle within `tolerance` of `point`, nearest first.
    static func handle(at point: CGPoint, for kind: Annotation.Kind, tolerance: Double) -> Handle? {
        handles(for: kind)
            .map { ($0.handle, distance($0.point, point)) }
            .filter { $0.1 <= tolerance }
            .min { $0.1 < $1.1 }?.0
    }

    // MARK: - Hit testing

    /// Topmost annotation under `point` (draw order reversed).
    static func topmost(in document: Document, at point: CGPoint, tolerance: Double) -> UUID? {
        document.drawOrder.reversed().first { hits($0, at: point, tolerance: tolerance) }?.id
    }

    /// Whether `point` touches the annotation. Unfilled shapes hit on their outline only, so
    /// objects inside them stay clickable.
    static func hits(_ annotation: Annotation, at point: CGPoint, tolerance: Double) -> Bool {
        let reach = tolerance + annotation.style.strokeWidth / 2
        switch annotation.kind {
        case let .arrow(start, end, .curved(control)):
            return distance(point, toPolyline: quadSamples(start, control, end)) <= reach
        case let .arrow(start, end, _), let .line(start, end):
            return distance(point, toSegment: start, end) <= reach
        case let .rectangle(rect, filled, _):
            let solid = filled || annotation.style.fillColor != nil
            return solid ? rect.standardized.insetBy(dx: -reach, dy: -reach).contains(point)
                : distance(point, toOutline: rect.standardized) <= reach
        case let .ellipse(rect):
            return hitsEllipse(rect.standardized, point, reach: reach, solid: annotation.style.fillColor != nil)
        case let .counter(_, center, radius):
            return distance(center, point) <= radius + tolerance
        case let .path(points, _), let .highlight(.path(points), _):
            return distance(point, toPolyline: points) <= reach
        case let .spotlight(shapes):
            return shapes.contains { $0.rect.standardized.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
        case .text, .blur, .pixelate, .imageLayer, .highlight:
            return annotation.kind.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    /// Annotations whose bounds intersect a rubber-band rect.
    static func annotations(in document: Document, intersecting rect: CGRect) -> Set<UUID> {
        let band = rect.standardized
        return Set(document.annotations.filter { $0.kind.bounds.intersects(band) }.map(\.id))
    }

    // MARK: - Resize

    /// New bounds when `handle` of `original` is dragged to `point`. With `constrain`, corner
    /// handles keep the original aspect ratio. The result is standardized.
    static func resized(_ original: CGRect, handle: Handle, to point: CGPoint, constrain: Bool) -> CGRect {
        var minX = original.minX, minY = original.minY, maxX = original.maxX, maxY = original.maxY
        switch handle {
        case .topLeft: (minX, minY) = (point.x, point.y)
        case .top: minY = point.y
        case .topRight: (maxX, minY) = (point.x, point.y)
        case .right: maxX = point.x
        case .bottomRight: (maxX, maxY) = (point.x, point.y)
        case .bottom: maxY = point.y
        case .bottomLeft: (minX, maxY) = (point.x, point.y)
        case .left: minX = point.x
        case .start, .end, .control: return original
        }
        var rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        if constrain, handle.isCorner, original.width > 0, original.height > 0 {
            rect = keepAspect(rect, of: original, anchoredOpposite: handle)
        }
        return rect.standardized
    }

    /// Moves a line or arrow endpoint, or the curved arrow's control point. With `constrain`,
    /// endpoints snap to 45° steps around the other end.
    static func movingPoint(_ kind: Annotation.Kind, handle: Handle, to point: CGPoint,
                            constrain: Bool) -> Annotation.Kind {
        switch (kind, handle) {
        case let (.arrow(_, end, style), .start):
            return .arrow(start: constrain ? snapAngle(point, around: end) : point, end: end, style: style)
        case let (.arrow(start, _, style), .end):
            return .arrow(start: start, end: constrain ? snapAngle(point, around: start) : point, style: style)
        case let (.arrow(start, end, .curved), .control):
            return .arrow(start: start, end: end, style: .curved(control: point))
        case let (.line(_, end), .start):
            return .line(start: constrain ? snapAngle(point, around: end) : point, end: end)
        case let (.line(start, _), .end):
            return .line(start: start, end: constrain ? snapAngle(point, around: start) : point)
        default:
            return kind
        }
    }

    // MARK: - Constraints

    /// Snaps `point` so the segment from `origin` is at a multiple of 45°, keeping its length.
    static func snapAngle(_ point: CGPoint, around origin: CGPoint) -> CGPoint {
        let dx = point.x - origin.x, dy = point.y - origin.y
        let length = hypot(dx, dy)
        guard length > 0 else { return point }
        let step = Double.pi / 4
        let angle = (atan2(dy, dx) / step).rounded() * step
        return CGPoint(x: origin.x + cos(angle) * length, y: origin.y + sin(angle) * length)
    }

    /// Square rect from `start` toward `end` (side = the longer drag axis).
    static func squared(from start: CGPoint, to end: CGPoint) -> CGRect {
        let side = max(abs(end.x - start.x), abs(end.y - start.y))
        let x = end.x >= start.x ? start.x : start.x - side
        let y = end.y >= start.y ? start.y : start.y - side
        return CGRect(x: x, y: y, width: side, height: side)
    }

    static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    // MARK: - Distances

    static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> Double {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    static func distance(_ point: CGPoint, toSegment start: CGPoint, _ end: CGPoint) -> Double {
        let dx = end.x - start.x, dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(point, start) }
        let fraction = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        return distance(point, CGPoint(x: start.x + fraction * dx, y: start.y + fraction * dy))
    }

    static func distance(_ point: CGPoint, toPolyline points: [CGPoint]) -> Double {
        guard let first = points.first else { return .infinity }
        guard points.count > 1 else { return distance(point, first) }
        return zip(points, points.dropFirst()).map { distance(point, toSegment: $0, $1) }.min() ?? .infinity
    }

    static func distance(_ point: CGPoint, toOutline rect: CGRect) -> Double {
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        return distance(point, toPolyline: corners + [corners[0]])
    }

    /// Points along a quadratic Bézier, for hit-testing curved arrows.
    static func quadSamples(_ start: CGPoint, _ control: CGPoint, _ end: CGPoint, count: Int = 24) -> [CGPoint] {
        (0...count).map { step -> CGPoint in
            let along = Double(step) / Double(count)
            let rest = 1 - along
            // Bernstein weights, kept as named values so the type checker stays fast.
            let w0: Double = rest * rest
            let w1: Double = 2 * rest * along
            let w2: Double = along * along
            let x: Double = w0 * start.x + w1 * control.x + w2 * end.x
            let y: Double = w0 * start.y + w1 * control.y + w2 * end.y
            return CGPoint(x: x, y: y)
        }
    }

    private static func hitsEllipse(_ rect: CGRect, _ point: CGPoint, reach: Double, solid: Bool) -> Bool {
        let radiusX = rect.width / 2, radiusY = rect.height / 2
        guard radiusX > 0, radiusY > 0 else { return distance(point, toOutline: rect) <= reach }
        let dx = (point.x - rect.midX) / radiusX, dy = (point.y - rect.midY) / radiusY
        let normalized = hypot(dx, dy)
        if solid, normalized <= 1 { return true }
        return abs(normalized - 1) * min(radiusX, radiusY) <= reach
    }

    /// Grows the dragged rect to the original aspect, keeping the corner opposite `handle` fixed.
    private static func keepAspect(_ rect: CGRect, of original: CGRect, anchoredOpposite handle: Handle) -> CGRect {
        let aspect = original.width / original.height
        var width = abs(rect.width), height = abs(rect.height)
        if width / max(height, 0.0001) > aspect { height = width / aspect } else { width = height * aspect }
        let anchor: CGPoint = switch handle {
        case .topLeft: CGPoint(x: original.maxX, y: original.maxY)
        case .topRight: CGPoint(x: original.minX, y: original.maxY)
        case .bottomLeft: CGPoint(x: original.maxX, y: original.minY)
        default: CGPoint(x: original.minX, y: original.minY)
        }
        let towardX = rect.width >= 0 ? 1.0 : -1.0, towardY = rect.height >= 0 ? 1.0 : -1.0
        let signX = (handle == .topLeft || handle == .bottomLeft) ? -towardX : towardX
        let signY = (handle == .topLeft || handle == .topRight) ? -towardY : towardY
        return CGRect(x: anchor.x, y: anchor.y, width: width * signX, height: height * signY).standardized
    }
}

import CoreGraphics
import Foundation

// Bounds and point mapping for annotation geometry, used by move and resize.

extension Annotation.Kind {
    /// Smallest rect containing the annotation's geometry (stroke width not included).
    /// `CGRect.null` for a path with no points.
    public var bounds: CGRect {
        switch self {
        case let .arrow(start, end, style):
            var points = [start, end]
            if case let .curved(control) = style { points.append(control) }
            return Self.boundingRect(points)
        case let .line(start, end):
            return Self.boundingRect([start, end])
        case let .rectangle(rect, _, _), let .ellipse(rect), let .text(_, _, _, rect),
             let .blur(rect, _, _), let .pixelate(rect, _, _), let .imageLayer(_, rect):
            return rect.standardized
        case let .counter(_, center, radius):
            return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        case let .path(points, _):
            return Self.boundingRect(points)
        case let .highlight(region, _):
            return region.bounds
        case let .spotlight(shapes):
            return shapes.reduce(CGRect.null) { $0.union($1.rect.standardized) }
        }
    }

    /// Returns a copy with every point passed through `transform`.
    /// `scale` multiplies radii that should grow with the shape (counter radius).
    public func mapped(scale: Double = 1, _ transform: (CGPoint) -> CGPoint) -> Self {
        switch self {
        case let .arrow(start, end, style):
            var newStyle = style
            if case let .curved(control) = style { newStyle = .curved(control: transform(control)) }
            return .arrow(start: transform(start), end: transform(end), style: newStyle)
        case let .line(start, end):
            return .line(start: transform(start), end: transform(end))
        case let .counter(number, center, radius):
            return .counter(number: number, center: transform(center), radius: radius * scale)
        case let .path(points, smoothed):
            return .path(points: points.map(transform), smoothed: smoothed)
        case let .highlight(region, color):
            return .highlight(region: region.mapped(transform), color: color)
        case let .spotlight(shapes):
            return .spotlight(shapes: shapes.map { $0.mapped(transform) })
        case .rectangle, .ellipse, .text, .blur, .pixelate, .imageLayer:
            return withRect(Self.mapRect(bounds, transform))
        }
    }

    /// Replaces the rect of a rect-based kind; other kinds are returned unchanged.
    func withRect(_ rect: CGRect) -> Self {
        switch self {
        case let .rectangle(_, filled, cornerRadius):
            .rectangle(rect: rect, filled: filled, cornerRadius: cornerRadius)
        case .ellipse: .ellipse(rect: rect)
        case let .text(string, preset, fontSize, _):
            .text(string: string, preset: preset, fontSize: fontSize, rect: rect)
        case let .blur(_, mode, radius): .blur(rect: rect, mode: mode, radius: radius)
        case let .pixelate(_, blockSize, randomize):
            .pixelate(rect: rect, blockSize: blockSize, randomize: randomize)
        case let .imageLayer(layerName, _): .imageLayer(layerName: layerName, rect: rect)
        case .arrow, .line, .counter, .path, .highlight, .spotlight: self
        }
    }

    static func boundingRect(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func mapRect(_ rect: CGRect, _ transform: (CGPoint) -> CGPoint) -> CGRect {
        let rect = rect.standardized
        return boundingRect([transform(CGPoint(x: rect.minX, y: rect.minY)),
                             transform(CGPoint(x: rect.maxX, y: rect.maxY))])
    }
}

extension Annotation.HighlightRegion {
    public var bounds: CGRect {
        switch self {
        case let .rect(rect): rect.standardized
        case let .path(points): Annotation.Kind.boundingRect(points)
        }
    }

    func mapped(_ transform: (CGPoint) -> CGPoint) -> Self {
        switch self {
        case let .rect(rect): .rect(rect: Annotation.Kind.mapRect(rect, transform))
        case let .path(points): .path(points: points.map(transform))
        }
    }
}

extension Annotation.SpotlightShape {
    public var rect: CGRect {
        switch self {
        case let .rect(rect), let .ellipse(rect): rect
        }
    }

    func mapped(_ transform: (CGPoint) -> CGPoint) -> Self {
        switch self {
        case let .rect(rect): .rect(rect: Annotation.Kind.mapRect(rect, transform))
        case let .ellipse(rect): .ellipse(rect: Annotation.Kind.mapRect(rect, transform))
        }
    }
}

import CoreGraphics
import Foundation
import ScreenCapKit

/// Turns a tool drag (or click) into annotation geometry. Pure, so it is unit-tested.
enum ToolDrag {
    /// Drags shorter than this (pixels) on a shape tool are treated as accidental.
    static let minimumDrag: Double = 3

    /// Annotation kind for a drag from `start` to `end` with `tool`. Nil when the drag is too
    /// short to make that object (except click tools: counter and text).
    static func kind(for tool: EditorTool, from start: CGPoint, to end: CGPoint, constrain: Bool,
                     options: ToolOptions, nextCounter: Int = 1) -> Annotation.Kind? {
        let length = EditorGeometry.distance(start, end)
        if tool == .counter {
            return .counter(number: nextCounter, center: end, radius: options.counterRadius)
        }
        if tool == .text, length < minimumDrag {
            return .text(string: "", preset: options.textPreset.rawValue, fontSize: options.fontSize,
                         rect: defaultTextRect(at: start, fontSize: options.fontSize))
        }
        guard length >= minimumDrag else { return nil }
        if tool == .line || tool == .arrow {
            return lineKind(tool, from: start, to: constrain ? EditorGeometry.snapAngle(end, around: start) : end,
                            arrow: options.arrow)
        }
        let rect = constrain ? EditorGeometry.squared(from: start, to: end) : EditorGeometry.rect(from: start, to: end)
        return rectKind(tool, rect: rect, options: options)
    }

    /// Freehand pencil or highlighter stroke from raw drag points.
    static func freehand(_ tool: EditorTool, points: [CGPoint], options: ToolOptions) -> Annotation.Kind? {
        guard let first = points.first else { return nil }
        let thinned = thin(points, minimumSpacing: 1.5)
        switch tool {
        case .pencil:
            return .path(points: thinned.count > 1 ? thinned : [first], smoothed: true)
        case .highlighter:
            guard thinned.count > 1 else { return nil }
            return .highlight(region: .path(points: thinned), color: options.highlightColor)
        default:
            return nil
        }
    }

    /// Default box for a click-to-type text object.
    static func defaultTextRect(at point: CGPoint, fontSize: Double) -> CGRect {
        CGRect(x: point.x, y: point.y - fontSize * 0.7, width: max(fontSize * 8, 160), height: fontSize * 1.6)
    }

    /// Control point for a new curved arrow: the midpoint, pushed sideways by a quarter of the length.
    static func defaultControl(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let dx = end.x - start.x, dy = end.y - start.y
        return CGPoint(x: mid.x + dy * 0.25, y: mid.y - dx * 0.25)
    }

    private static func lineKind(_ tool: EditorTool, from start: CGPoint, to end: CGPoint,
                                 arrow: ArrowChoice) -> Annotation.Kind {
        guard tool == .arrow else { return .line(start: start, end: end) }
        let style: Annotation.ArrowStyle = switch arrow {
        case .straight: .straight
        case .tapered: .tapered
        case .doubleHeaded: .doubleHeaded
        case .curved: .curved(control: defaultControl(from: start, to: end))
        }
        return .arrow(start: start, end: end, style: style)
    }

    private static func rectKind(_ tool: EditorTool, rect: CGRect, options: ToolOptions) -> Annotation.Kind? {
        switch tool {
        case .rectangle: .rectangle(rect: rect, filled: false, cornerRadius: options.cornerRadius)
        case .filledRectangle: .rectangle(rect: rect, filled: true, cornerRadius: options.cornerRadius)
        case .ellipse: .ellipse(rect: rect)
        case .text: .text(string: "", preset: options.textPreset.rawValue, fontSize: options.fontSize, rect: rect)
        case .blur: .blur(rect: rect, mode: options.blurMode, radius: options.blurRadius)
        case .pixelate:
            .pixelate(rect: rect, blockSize: options.pixelateBlockSize, randomize: options.pixelateRandomize)
        case .spotlight:
            .spotlight(shapes: [options.spotlightShape == .ellipse ? .ellipse(rect: rect) : .rect(rect: rect)])
        case .highlighter: .highlight(region: .rect(rect: rect), color: options.highlightColor)
        case .select, .arrow, .line, .counter, .pencil, .crop: nil
        }
    }

    /// Drops points closer than `minimumSpacing` to the last kept one (always keeps the last).
    static func thin(_ points: [CGPoint], minimumSpacing: Double) -> [CGPoint] {
        guard var last = points.first else { return [] }
        var result = [last]
        for point in points.dropFirst() where EditorGeometry.distance(point, last) >= minimumSpacing {
            result.append(point)
            last = point
        }
        if let final = points.last, final != result.last, points.count > 1 { result.append(final) }
        return result
    }
}

/// Crop presets and snapping (PLAN §3.3: free, 1:1, 4:3, 16:9, custom; snaps to edges).
enum CropAspect: Hashable, Sendable, CaseIterable {
    case free, square, fourThree, sixteenNine, custom

    var title: String {
        switch self {
        case .free: "Free"
        case .square: "1:1"
        case .fourThree: "4:3"
        case .sixteenNine: "16:9"
        case .custom: "Custom"
        }
    }

    /// Width ÷ height, or nil for free. `custom` uses the caller's ratio.
    func ratio(custom: CGSize) -> Double? {
        switch self {
        case .free: nil
        case .square: 1
        case .fourThree: 4.0 / 3.0
        case .sixteenNine: 16.0 / 9.0
        case .custom: custom.width > 0 && custom.height > 0 ? custom.width / custom.height : nil
        }
    }
}

enum CropMath {
    /// Snap distance in image pixels.
    static let snapThreshold: Double = 8

    /// Crop rect for a drag from `start` to `end`: aspect-constrained when `ratio` is set,
    /// snapped to `edges` within `threshold`, and clamped to `bounds`.
    static func rect(from start: CGPoint, to end: CGPoint, ratio: Double?, bounds: CGRect,
                     edges: CropEdges = CropEdges(), threshold: Double = snapThreshold) -> CGRect {
        var target = end
        if ratio == nil {
            target = CGPoint(x: snap(end.x, to: edges.xEdges + [bounds.minX, bounds.maxX], threshold: threshold),
                             y: snap(end.y, to: edges.yEdges + [bounds.minY, bounds.maxY], threshold: threshold))
        }
        var rect = EditorGeometry.rect(from: start, to: target)
        if let ratio, ratio > 0, rect.height > 0 {
            rect = constrained(rect, from: start, toward: end, ratio: ratio)
        }
        return rect.intersection(bounds).standardized
    }

    /// Snaps each edge of `rect` independently to the nearest edge within `threshold`.
    static func snapped(_ rect: CGRect, to edges: CropEdges, bounds: CGRect,
                        threshold: Double = snapThreshold) -> CGRect {
        let xEdges = edges.xEdges + [bounds.minX, bounds.maxX], yEdges = edges.yEdges + [bounds.minY, bounds.maxY]
        let minX = snap(rect.minX, to: xEdges, threshold: threshold)
        let maxX = snap(rect.maxX, to: xEdges, threshold: threshold)
        let minY = snap(rect.minY, to: yEdges, threshold: threshold)
        let maxY = snap(rect.maxY, to: yEdges, threshold: threshold)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).intersection(bounds)
    }

    static func snap(_ value: Double, to candidates: [Double], threshold: Double) -> Double {
        guard let nearest = candidates.min(by: { abs($0 - value) < abs($1 - value) }),
              abs(nearest - value) <= threshold else { return value }
        return nearest
    }

    /// Integral pixel rect inside the image, for the actual crop.
    static func pixelRect(_ rect: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(origin: .zero, size: imageSize).intersection(rect.standardized.integral)
    }

    private static func constrained(_ rect: CGRect, from start: CGPoint, toward end: CGPoint,
                                    ratio: Double) -> CGRect {
        var width = rect.width, height = rect.height
        if width / height > ratio { height = width / ratio } else { width = height * ratio }
        let x = end.x >= start.x ? start.x : start.x - width
        let y = end.y >= start.y ? start.y : start.y - height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Detected UI edges the crop snaps to, in image pixels.
struct CropEdges: Equatable, Sendable {
    var xEdges: [Double] = []
    var yEdges: [Double] = []
}

/// Zoom levels and fit math for the canvas. Magnification 1 shows one image pixel per view point.
enum ZoomMath {
    static let steps: [Double] = [0.05, 0.1, 0.125, 0.25, 0.333, 0.5, 0.667, 0.75, 1, 1.5, 2, 3, 4, 6, 8]
    static var minimum: Double { steps[0] }
    static var maximum: Double { steps[steps.count - 1] }

    /// Largest magnification that shows all of `content` inside `viewport` less `margin` on each
    /// side, never above `maxScale` (so small images aren't blown up).
    static func fit(content: CGSize, in viewport: CGSize, margin: Double = 20, maxScale: Double = 1) -> Double {
        guard content.width > 0, content.height > 0 else { return 1 }
        let width = max(viewport.width - margin * 2, 1), height = max(viewport.height - margin * 2, 1)
        return clamp(min(width / content.width, height / content.height, maxScale))
    }

    static func zoomIn(from current: Double) -> Double {
        steps.first { $0 > current * 1.001 } ?? maximum
    }

    static func zoomOut(from current: Double) -> Double {
        steps.last { $0 < current * 0.999 } ?? minimum
    }

    static func clamp(_ value: Double) -> Double {
        min(max(value, minimum), maximum)
    }
}

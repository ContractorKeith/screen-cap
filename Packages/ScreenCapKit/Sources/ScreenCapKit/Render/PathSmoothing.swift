import CoreGraphics
import Foundation

/// Smoothing for freehand pencil input.
public enum PathSmoothing {
    /// Samples a uniform Catmull-Rom spline through `points`, `samplesPerSegment` points per
    /// segment. The result starts at the first point and passes exactly through every input
    /// point; the end points are repeated as their own outer neighbors. Fewer than three
    /// points are returned unchanged.
    public static func catmullRom(points: [CGPoint], samplesPerSegment: Int = 8) -> [CGPoint] {
        guard points.count > 2, samplesPerSegment > 1 else { return points }
        var result = [points[0]]
        result.reserveCapacity(1 + (points.count - 1) * samplesPerSegment)
        for index in 0..<(points.count - 1) {
            let segment = Segment(
                before: points[max(index - 1, 0)], start: points[index],
                end: points[index + 1], after: points[min(index + 2, points.count - 1)]
            )
            for step in 1..<samplesPerSegment {
                result.append(segment.point(at: Double(step) / Double(samplesPerSegment)))
            }
            result.append(segment.end)
        }
        return result
    }

    /// One span of the spline, from `start` to `end`, shaped by their outer neighbors.
    struct Segment {
        var before: CGPoint
        var start: CGPoint
        var end: CGPoint
        var after: CGPoint

        /// Uniform Catmull-Rom at `fraction` in 0...1.
        func point(at fraction: Double) -> CGPoint {
            let squared = fraction * fraction
            let cubed = squared * fraction
            func axis(_ before: Double, _ start: Double, _ end: Double, _ after: Double) -> Double {
                0.5 * (2 * start + (end - before) * fraction
                    + (2 * before - 5 * start + 4 * end - after) * squared
                    + (3 * start - before - 3 * end + after) * cubed)
            }
            return CGPoint(x: axis(before.x, start.x, end.x, after.x), y: axis(before.y, start.y, end.y, after.y))
        }
    }
}

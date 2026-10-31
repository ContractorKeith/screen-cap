import CoreGraphics
import Foundation

/// Finds text-line boxes so the highlighter can snap its height to the line under the stroke.
public struct TextLineDetector: Sendable {
    public init() {}

    /// Text-line rects in image pixels (top-left origin), sorted top to bottom, then left to right.
    ///
    /// Uses fast recognition rather than `VNDetectTextRectanglesRequest`: the latter splits lines
    /// into word-ish regions, while recognition observations are whole lines.
    public func lines(in image: CGImage) async throws -> [CGRect] {
        let text = try await TextRecognizer.recognize(
            in: image, languages: nil, level: .fast, usesLanguageCorrection: false
        )
        return text.lines.map(\.boundingBox).sorted { lhs, rhs in
            abs(lhs.midY - rhs.midY) < min(lhs.height, rhs.height) / 2 ? lhs.minX < rhs.minX : lhs.minY < rhs.minY
        }
    }

    /// The line under a highlighter stroke: the one the stroke overlaps most vertically
    /// (among lines it also overlaps horizontally). Ties go to the line whose center is closest
    /// to the stroke's center. Nil when the stroke isn't over any line.
    public static func snapHeight(for strokeRect: CGRect, lines: [CGRect]) -> CGRect? {
        func verticalOverlap(_ line: CGRect) -> CGFloat {
            min(strokeRect.maxY, line.maxY) - max(strokeRect.minY, line.minY)
        }
        func distance(_ line: CGRect) -> CGFloat { abs(line.midY - strokeRect.midY) }

        let candidates = lines.filter { line in
            let horizontal = min(strokeRect.maxX, line.maxX) - max(strokeRect.minX, line.minX)
            // A zero-height stroke (a straight drag) still counts if it lies within the line.
            return horizontal > 0 && verticalOverlap(line) >= 0 && line.height > 0
        }
        return candidates.min { lhs, rhs in
            let (left, right) = (verticalOverlap(lhs), verticalOverlap(rhs))
            return left != right ? left > right : distance(lhs) < distance(rhs)
        }
    }
}

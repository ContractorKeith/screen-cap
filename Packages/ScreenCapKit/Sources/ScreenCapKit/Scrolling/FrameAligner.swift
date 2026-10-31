// Scroll offset between two consecutive frames (PLAN §5.4 step 3).
import CoreGraphics
import Vision

/// Finds how far content scrolled between two same-size frames.
///
/// Vision's translational registration proposes an offset; line-hash matching confirms it.
/// If Vision is unavailable or wrong, an exhaustive line-hash search decides. Only forward
/// scrolling (content moving up or left) is detected.
public struct FrameAligner: Sendable {
    /// Outcome of aligning two frames.
    public enum Alignment: Equatable, Sendable {
        /// The frames show the same content in the same place.
        case noMovement
        /// Content moved this many pixels along the axis (next line `i` == previous line `i + n`).
        case offset(Int)
        /// No offset explains the frames well enough.
        case unrelated
    }

    /// Fraction of informative overlapping lines that must match for an offset to count.
    public var minimumConfidence: Double
    /// Smallest overlap kept when searching, as a fraction of the frame length.
    public var minimumOverlapFraction: Double
    /// Ask Vision for a first guess before the exhaustive search.
    public var usesVision: Bool

    public init(minimumConfidence: Double = 0.6, minimumOverlapFraction: Double = 0.2, usesVision: Bool = true) {
        self.minimumConfidence = minimumConfidence
        self.minimumOverlapFraction = minimumOverlapFraction
        self.usesVision = usesVision
    }

    /// Aligns `next` against `previous` along `axis`. Frames of different sizes are `.unrelated`.
    public func align(previous: CGImage, next: CGImage, axis: ScrollAxis) -> Alignment {
        guard previous.width == next.width, previous.height == next.height else { return .unrelated }
        let space = PixelFrame.workingSpace(for: previous)
        guard let previousFrame = PixelFrame(image: previous, colorSpace: space),
              let nextFrame = PixelFrame(image: next, colorSpace: space) else { return .unrelated }
        let hint = usesVision ? Self.visionOffset(previous: previous, next: next, axis: axis) : nil
        return align(
            previous: previousFrame.lineHashes(along: axis), next: nextFrame.lineHashes(along: axis), hint: hint
        )
    }

    /// Hash-level alignment. `hint` is a candidate offset (from Vision) checked first.
    func align(previous: [LineHash], next: [LineHash], hint: Int?) -> Alignment {
        let count = next.count
        guard count > 0, previous.count == count else { return .unrelated }
        if previous == next { return .noMovement }
        let minimumOverlap = max(8, Int(Double(count) * minimumOverlapFraction))
        let maxOffset = count - minimumOverlap
        guard maxOffset >= 0 else { return .unrelated }

        // Vision's guess, give or take a couple of pixels for rounding.
        if let hint {
            let candidates = (hint - 2...hint + 2).filter { (0...maxOffset).contains($0) }
            if let best = bestOffset(in: candidates, previous: previous, next: next) {
                return best.offset == 0 ? .noMovement : .offset(best.offset)
            }
        }
        guard let best = bestOffset(in: Array(0...maxOffset), previous: previous, next: next) else {
            return .unrelated
        }
        return best.offset == 0 ? .noMovement : .offset(best.offset)
    }

    /// The highest-scoring offset that reaches `minimumConfidence`; ties go to the smaller offset.
    private func bestOffset(
        in candidates: [Int], previous: [LineHash], next: [LineHash]
    ) -> (offset: Int, score: Double)? {
        var best: (offset: Int, score: Double)?
        for offset in candidates {
            let score = Self.score(offset: offset, previous: previous, next: next)
            if score >= minimumConfidence, score > (best?.score ?? -1) { best = (offset, score) }
        }
        return best
    }

    /// Fraction of informative lines in the overlap that match at `offset`.
    /// Blank lines are skipped: they would match at any offset.
    static func score(offset: Int, previous: [LineHash], next: [LineHash]) -> Double {
        var informative = 0
        var matched = 0
        for index in 0..<(next.count - offset) where next[index].isInformative {
            informative += 1
            if next[index] == previous[index + offset] { matched += 1 }
        }
        guard informative >= 8 else { return 0 }
        return Double(matched) / Double(informative)
    }

    /// Vision's translational estimate as a non-negative pixel offset along `axis`, if any.
    /// The sign convention is not relied on: hash confirmation decides.
    static func visionOffset(previous: CGImage, next: CGImage, axis: ScrollAxis) -> Int? {
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: next, options: [:])
        let handler = VNImageRequestHandler(cgImage: previous, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let observation = request.results?.first else { return nil }
        let transform = observation.alignmentTransform
        let shift = axis == .vertical ? transform.ty : transform.tx
        guard shift.isFinite else { return nil }
        return Int(abs(shift).rounded())
    }
}

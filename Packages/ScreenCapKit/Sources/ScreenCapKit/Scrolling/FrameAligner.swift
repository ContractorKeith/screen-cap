// Scroll offset between two consecutive frames (PLAN §5.4 step 3).
import CoreGraphics
import Vision

/// Finds how far content scrolled between two same-size frames.
///
/// An exhaustive search scores every offset by matching windows of line hashes. When several
/// offsets match equally well (repetitive content), Vision's translational estimate, the
/// auto-scroll step and the previous step break the tie. Only forward scrolling (content
/// moving up or left) is detected.
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

    /// What the caller expects the offset to be, used only to break ties between offsets that
    /// match equally well (repetitive content such as logs, tables and Terminal output).
    public struct Prior: Equatable, Sendable {
        /// The auto-scroll step in pixels. Content moves by about a whole multiple of it per frame.
        public var expectedStep: Int?
        /// The offset accepted for the previous frame pair.
        public var previousStep: Int?

        public init(expectedStep: Int? = nil, previousStep: Int? = nil) {
            self.expectedStep = expectedStep
            self.previousStep = previousStep
        }
    }

    /// Fraction of informative overlapping lines that must match for an offset to count.
    public var minimumConfidence: Double
    /// Smallest overlap kept when searching, as a fraction of the frame length.
    public var minimumOverlapFraction: Double
    /// Ask Vision for a first guess before the exhaustive search.
    public var usesVision: Bool

    /// Lines hashed together per comparison: single lines repeat too often (blank-ish text rows).
    static let windowSize = 4
    /// Offsets scoring within this of the best are equally good candidates.
    static let tieTolerance = 0.02
    /// Overlap is never searched below this many lines.
    static let minimumOverlapLines = 16

    public init(minimumConfidence: Double = 0.6, minimumOverlapFraction: Double = 0.1, usesVision: Bool = true) {
        self.minimumConfidence = minimumConfidence
        self.minimumOverlapFraction = minimumOverlapFraction
        self.usesVision = usesVision
    }

    /// Aligns `next` against `previous` along `axis`. Frames of different sizes are `.unrelated`.
    public func align(previous: CGImage, next: CGImage, axis: ScrollAxis, prior: Prior = Prior()) -> Alignment {
        guard previous.width == next.width, previous.height == next.height else { return .unrelated }
        let space = PixelFrame.workingSpace(for: previous)
        guard let previousFrame = PixelFrame(image: previous, colorSpace: space),
              let nextFrame = PixelFrame(image: next, colorSpace: space) else { return .unrelated }
        let hint = usesVision ? Self.visionOffset(previous: previous, next: next, axis: axis) : nil
        return align(
            previous: previousFrame.lineHashes(along: axis), next: nextFrame.lineHashes(along: axis),
            hint: hint, prior: prior
        )
    }

    /// Hash-level alignment. `hint` (Vision) and `prior` only break ties between equally good offsets.
    func align(previous: [LineHash], next: [LineHash], hint: Int?, prior: Prior = Prior()) -> Alignment {
        let count = next.count
        guard count > 0, previous.count == count else { return .unrelated }
        // Only byte-identical frames are still; any real shift, however small, is motion.
        if previous == next { return .noMovement }
        let minimumOverlap = max(Self.minimumOverlapLines, Int(Double(count) * minimumOverlapFraction))
        let maxOffset = count - minimumOverlap
        guard maxOffset >= 0, count >= Self.windowSize else { return .unrelated }

        let previousWindows = Self.windows(previous)
        let nextWindows = Self.windows(next)
        let scores = (0...maxOffset).map { Self.score(offset: $0, previous: previousWindows, next: nextWindows) }
        guard let best = scores.max(), best >= minimumConfidence else { return .unrelated }
        let candidates = scores.indices.filter { scores[$0] >= max(minimumConfidence, best - Self.tieTolerance) }
        let offset = Self.choose(candidates, scores: scores, hint: hint, prior: prior)
        return offset == 0 ? .noMovement : .offset(offset)
    }

    /// Picks one offset from equally good candidates. One tight cluster is unambiguous; otherwise
    /// (periodic content) prefer, in order: a multiple of the auto-scroll step, Vision's estimate,
    /// the previous step, then the smallest motion.
    static func choose(_ candidates: [Int], scores: [Double], hint: Int?, prior: Prior) -> Int {
        guard let low = candidates.first, let high = candidates.last else { return 0 }
        if high - low <= 2 {
            return candidates.max { scores[$0] < scores[$1] } ?? low
        }
        func nearest(_ distance: (Int) -> Int) -> Int {
            candidates.min { distance($0) < distance($1) } ?? low
        }
        if let step = prior.expectedStep, step > 0 {
            return nearest { offset in
                let multiple = max(1, Int((Double(offset) / Double(step)).rounded()))
                return abs(offset - multiple * step)
            }
        }
        if let hint, candidates.contains(where: { abs($0 - hint) <= 3 }) {
            return nearest { abs($0 - hint) }
        }
        if let previous = prior.previousStep, previous > 0 {
            return nearest { abs($0 - previous) }
        }
        return low
    }

    /// Hashes of `windowSize` consecutive lines; a window carries detail if any of its lines does.
    static func windows(_ lines: [LineHash]) -> [LineHash] {
        guard lines.count >= windowSize else { return [] }
        return (0...(lines.count - windowSize)).map { start in
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            var informative = false
            for line in lines[start..<start + windowSize] {
                hash = (hash ^ line.value) &* 0x0000_0100_0000_01b3
                informative = informative || line.isInformative
            }
            return LineHash(value: hash, isInformative: informative)
        }
    }

    /// Fraction of informative overlapping windows that match at `offset`.
    /// Blank windows are skipped: they would match at any offset.
    static func score(offset: Int, previous: [LineHash], next: [LineHash]) -> Double {
        var informative = 0
        var matched = 0
        for index in 0..<max(0, next.count - offset) where next[index].isInformative {
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

// Scroll offset between two consecutive frames (PLAN §5.4 step 3).
import CoreGraphics
import Vision

/// Finds how far content scrolled between two same-size frames.
///
/// An exhaustive search scores every offset by matching windows of line hashes. When several
/// offsets match equally well (repetitive content such as Terminal output and tables), only real
/// evidence picks one: windows that occur once in each frame ("anchors") and line up at one
/// offset, or an auto-scroll distance that exactly one candidate matches. Otherwise the frames
/// are `.ambiguous` and the caller marks a gap instead of guessing. Vision's translational
/// estimate aliases to the wrong period on such content, so it only arbitrates between offsets
/// that anchors already support. Only forward scrolling (content moving up or left) is detected.
public struct FrameAligner: Sendable {
    /// Outcome of aligning two frames.
    public enum Alignment: Equatable, Sendable {
        /// The frames show the same content in the same place.
        case noMovement
        /// Content moved this many pixels along the axis (next line `i` == previous line `i + n`).
        case offset(Int)
        /// Several offsets match equally well and nothing tells them apart (repeating rows).
        case ambiguous
        /// No offset explains the frames well enough.
        case unrelated
    }

    /// What the caller knows about the motion, used only to break ties between offsets that
    /// match equally well.
    public struct Prior: Equatable, Sendable {
        /// Pixels the auto-scroller posted since the previous frame. Trusted only when exactly
        /// one candidate lies within `stepTolerance` of it.
        public var expectedStep: Int?

        public init(expectedStep: Int? = nil) {
            self.expectedStep = expectedStep
        }
    }

    /// Fraction of informative overlapping lines that must match for an offset to count.
    public var minimumConfidence: Double
    /// Smallest overlap kept when searching, as a fraction of the frame length.
    public var minimumOverlapFraction: Double
    /// Ask Vision to choose between offsets that anchors support equally.
    public var usesVision: Bool

    /// Lines hashed together per comparison: single lines repeat too often (blank-ish text rows).
    static let windowSize = 4
    /// Offsets scoring within this of the best are equally good candidates.
    static let tieTolerance = 0.02
    /// Overlap is never searched below this many lines.
    static let minimumOverlapLines = 16
    /// Anchors needed before they decide between candidates.
    static let minimumAnchors = 3
    /// How close (pixels) a candidate must be to the auto-scroll distance.
    static let stepTolerance = 3

    public init(minimumConfidence: Double = 0.6, minimumOverlapFraction: Double = 0.05, usesVision: Bool = true) {
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
        return align(
            previous: previousFrame.lineHashes(along: axis), next: nextFrame.lineHashes(along: axis),
            hint: { usesVision ? Self.visionOffset(previous: previous, next: next, axis: axis) : nil },
            prior: prior
        )
    }

    /// Hash-level alignment. `hint` (Vision, computed only when needed) and `prior` only break ties.
    func align(previous: [LineHash], next: [LineHash], hint: () -> Int?, prior: Prior = Prior()) -> Alignment {
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
        let clusters = Self.clusters(candidates)
        let offset: Int?
        if clusters.count == 1 {
            offset = Self.best(in: clusters[0], scores: scores)
        } else {
            let votes = Self.anchorVotes(previous: previousWindows, next: nextWindows)
            offset = Self.choose(clusters, scores: scores, votes: votes, hint: hint, prior: prior)
        }
        guard let offset else { return .ambiguous }
        return offset == 0 ? .noMovement : .offset(offset)
    }

    /// Candidates split into runs of near-neighbours (one real offset smears over a pixel or two).
    static func clusters(_ candidates: [Int]) -> [[Int]] {
        candidates.reduce(into: [[Int]]()) { result, offset in
            if let last = result.last?.last, offset - last <= 2 {
                result[result.count - 1].append(offset)
            } else {
                result.append([offset])
            }
        }
    }

    static func best(in cluster: [Int], scores: [Double]) -> Int {
        cluster.max { scores[$0] < scores[$1] } ?? cluster[0]
    }

    /// Picks one of several equally good clusters, or nil when nothing tells them apart:
    /// 1. anchors, if they back one cluster clearly (Vision decides between backed clusters);
    /// 2. the auto-scroll distance, if exactly one cluster lies within `stepTolerance` of it.
    static func choose(_ clusters: [[Int]], scores: [Double], votes: [Int: Int], hint: () -> Int?,
                       prior: Prior) -> Int? {
        let support = clusters.map { cluster in cluster.reduce(0) { $0 + votes[$1, default: 0] } }
        if let top = support.max(), top >= minimumAnchors {
            let backed = clusters.indices.filter { support[$0] * 4 > top }
            if backed.count == 1 { return best(in: clusters[backed[0]], scores: scores) }
            if let hint = hint(),
               let match = backed.first(where: { clusters[$0].contains { abs($0 - hint) <= 3 } }) {
                return best(in: clusters[match], scores: scores)
            }
            return nil
        }
        if let step = prior.expectedStep, step > 0 {
            let near = clusters.filter { $0.contains { abs($0 - step) <= stepTolerance } }
            if near.count == 1 { return near[0].min { abs($0 - step) < abs($1 - step) } }
        }
        return nil
    }

    /// Offsets voted for by informative windows that occur exactly once in each frame:
    /// such a window is the same piece of content, so its displacement is the scroll.
    static func anchorVotes(previous: [LineHash], next: [LineHash]) -> [Int: Int] {
        func uniqueIndices(_ windows: [LineHash]) -> [UInt64: Int] {
            var seen: [UInt64: Int] = [:]
            var repeated = Set<UInt64>()
            for (index, window) in windows.enumerated() where window.isInformative {
                if seen.updateValue(index, forKey: window.value) != nil { repeated.insert(window.value) }
            }
            return seen.filter { !repeated.contains($0.key) }
        }
        let inPrevious = uniqueIndices(previous)
        var votes: [Int: Int] = [:]
        for (value, nextIndex) in uniqueIndices(next) {
            guard let previousIndex = inPrevious[value], previousIndex >= nextIndex else { continue }
            votes[previousIndex - nextIndex, default: 0] += 1
        }
        return votes
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

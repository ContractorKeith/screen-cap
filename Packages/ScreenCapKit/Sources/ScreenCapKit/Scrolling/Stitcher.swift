// Stitches scrolled frames into one long image (PLAN §5.4 steps 3–5).
import CoreGraphics

/// Builds a long screenshot from frames of a scrolling region.
///
/// Works in pixels; `scale` is metadata for the caller (1 or 2 for Retina). Each frame is
/// aligned against the last accepted one, still frames are dropped, sticky edges are trimmed
/// and only the newly revealed strip is appended. The leading edge (header) is kept once at
/// the start, the trailing edge (footer) once at the end.
///
/// A frame that can't be placed against the last one is held back:
/// - `.unrelated` (no overlap): if the next frame can't be placed either, the content really
///   jumped (scrolled faster than one region per frame).
/// - `.ambiguous` (repeating rows match at several offsets): later frames that are just as
///   ambiguous replace it, waiting for one that lines up.
/// When a later frame lines up with the last placed one, the held frame was a transient
/// (animation, lazy load, an in-between scroll position) and is dropped. Otherwise the held frame
/// is appended after a dashed seam marker, reported as `.gapDetected`, and stitching
/// continues from it. `finish()` keeps a frame still held when the capture stops the same way.
///
/// With auto-scroll (#112) the scroll distance is known, so it is the ground truth:
/// - Lines are compared with noise tolerance: live captures carry dither fixed to the screen, so
///   moved content never matches byte for byte.
/// - The step is measured: frames that line up at one offset only give the pixels the page
///   moves per posted pixel (Terminal moves about 1.5×). On repeating rows, the offset the
///   measured step predicts decides between equally good matches; Vision and anchors don't.
/// - A held frame kept after a seam starts after the last stitched row: it goes where the measured
///   step puts it if it matches the last placed frame there, else where it overlaps that frame
///   most. Rows may be missing at a seam, but none are appended twice.
public actor Stitcher {
    /// What happened to one appended frame.
    public enum AppendOutcome: Equatable, Sendable {
        /// The first frame; it seeds the canvas.
        case started
        /// Content moved; this many new lines were added (0 if the strip was all fixed edge).
        case appended(lines: Int)
        /// Same content as the last accepted frame; dropped.
        case noMovement
        /// Could not be aligned (different size, animation, a jump); held back or dropped.
        case unrelated
        /// Repeating content matched at several offsets and nothing told them apart; held back.
        case ambiguous
        /// The content jumped past the last frame: a seam marker and the held frame were
        /// appended, plus this frame's new strip; `lines` counts all added lines.
        case gapDetected(lines: Int)
        /// The `maxLength` cap is reached; nothing more is added.
        case maxLengthReached
    }

    public let axis: ScrollAxis
    /// Pixels per point of the source display. Metadata only.
    public let scale: CGFloat
    /// Cap on the stitched length along `axis`, in pixels, footer included.
    public let maxLength: Int
    private let aligner: FrameAligner
    /// Pixels auto-scroll posted since the last placed frame, if auto-scrolling.
    public private(set) var expectedStep: Int?
    /// Pixels one auto-scroll step posts; `expectedStep` is a whole number of them.
    public private(set) var stepUnit: Int?
    /// The step measured on this page.
    private var gauge = StepGauge()
    /// Auto-scroll was on for some frame: align with noise tolerance.
    private var autoScrolled = false

    private struct Accepted {
        let image: CGImage
        let frame: PixelFrame
        let hashes: [LineHash]
        let profiles: LineProfiles
        /// Content coordinate of the frame's line 0 (the first frame is at 0).
        let position: Int

        func moved(to position: Int) -> Accepted {
            Accepted(image: image, frame: frame, hashes: hashes, profiles: profiles, position: position)
        }
    }

    private var first: Accepted?
    private var last: Accepted?
    /// Why a frame is held back.
    private enum Hold { case unrelated, ambiguous }
    /// A frame that couldn't be placed against `last`, waiting to see whether the content jumped.
    private struct Held {
        let frame: Accepted
        let reason: Hold
        /// Pixels posted between `last` and it.
        let posted: Int?
    }
    private var pending: Held?
    private var edges = FixedEdges.none
    /// Edges are known once a pair aligned; until then a gap guesses them (`solidEdges`).
    private var edgesKnown = false
    private var canvas: GrowingCanvas?
    /// Content coordinate one past the last line on the canvas.
    private var canvasEnd = 0
    private var isFull = false

    public init(axis: ScrollAxis = .vertical, scale: CGFloat = 1, maxLength: Int = 50_000,
                aligner: FrameAligner = FrameAligner()) {
        self.axis = axis
        self.scale = scale
        self.maxLength = max(1, maxLength)
        self.aligner = aligner
    }

    /// The fixed edges detected so far.
    public var fixedEdges: FixedEdges { edges }

    /// Sets the pixels auto-scroll posted since the last placed frame (nil while scrolling manually)
    /// and, optionally, the pixels of one step. Once a step is measured on this page, ties on
    /// repetitive content go to the offset it predicts; before that, to the posted distance if it
    /// matches exactly one offset.
    public func setExpectedStep(_ step: Int?, unit: Int? = nil) {
        expectedStep = step
        stepUnit = unit
        if step != nil { autoScrolled = true }
    }

    /// Content pixels moved per posted pixel, measured on frames that lined up unambiguously.
    /// Nil until one did.
    public var measuredScale: Double? { gauge.scale }

    /// Pixels at the end of each line left out of noise-tolerant matching: an overlay scroll bar
    /// (16 pt) moves on its own while the content scrolls under it (#126).
    var scrollBarMargin: Int { Int((16 * scale).rounded()) }

    /// Lines in a gap's seam marker.
    var seamThickness: Int { max(2, Int((2 * scale).rounded())) }

    /// Aligns `frame` and appends its new strip.
    @discardableResult
    public func append(frame image: CGImage) -> AppendOutcome {
        guard let first, let last else {
            guard let frame = PixelFrame(image: image) else { return .unrelated }
            let seed = Accepted(image: image, frame: frame, hashes: frame.lineHashes(along: axis),
                                profiles: frame.lineProfiles(along: axis, trailingMargin: scrollBarMargin), position: 0)
            self.first = seed
            self.last = seed
            return .started
        }
        guard !isFull else { return .maxLengthReached }
        guard image.width == first.frame.width, image.height == first.frame.height,
              let frame = PixelFrame(image: image, colorSpace: first.frame.context.colorSpace) else {
            return .unrelated
        }
        let next = Accepted(image: image, frame: frame, hashes: frame.lineHashes(along: axis),
                            profiles: frame.lineProfiles(along: axis, trailingMargin: scrollBarMargin), position: 0)
        let posted = expectedStep

        let (alignment, evidence) = align(next, to: last, posted: posted)
        switch alignment {
        case .noMovement:
            pending = nil
            return .noMovement
        case .offset(let offset):
            pending = nil
            if evidence == .unique || evidence == .anchors {
                gauge.measure(offset: offset, posted: posted, unit: stepUnit)
            }
            return appendStrip(of: next, offset: offset, after: last)
        case .unrelated, .ambiguous:
            let reason: Hold = alignment == .ambiguous ? .ambiguous : .unrelated
            guard let held = pending else {
                pending = Held(frame: next, reason: reason, posted: posted)
                return reason == .ambiguous ? .ambiguous : .unrelated
            }
            // Still ambiguous against the held frame too: it may overlap either, so keep waiting.
            let sinceHeld = Self.distance(from: held.posted, to: posted)
            if held.reason == .ambiguous,
               [.ambiguous, .noMovement].contains(align(next, to: held.frame, posted: sinceHeld).alignment) {
                pending = Held(frame: next, reason: .ambiguous, posted: posted)
                return .ambiguous
            }
            pending = nil
            return appendJump(held: held.frame, posted: held.posted, then: next, posted: posted)
        }
    }

    /// Pixels posted between two frames, given the pixels posted up to each since the last placed one.
    private static func distance(from earlier: Int?, to later: Int?) -> Int? {
        guard let earlier, let later, later > earlier else { return nil }
        return later - earlier
    }

    /// Two frames in a row past `last`: the content jumped. Keeps the held frame after a seam,
    /// then appends what `next` adds beyond it.
    private func appendJump(held gap: Accepted, posted heldPosted: Int?, then next: Accepted,
                            posted: Int?) -> AppendOutcome {
        let anchor = appendGap(gap, posted: heldPosted)
        var lines = anchor.lines
        if isFull { return .maxLengthReached }
        let sinceHeld = Self.distance(from: heldPosted, to: posted)
        switch align(next, to: anchor.accepted, posted: sinceHeld).alignment {
        case .offset(let offset):
            let outcome = appendStrip(of: next, offset: offset, after: anchor.accepted)
            guard case .appended(let added) = outcome else { return outcome }
            lines += added
        case .noMovement:
            break
        case .unrelated:
            pending = Held(frame: next, reason: .unrelated, posted: posted)
        case .ambiguous:
            pending = Held(frame: next, reason: .ambiguous, posted: posted)
        }
        return .gapDetected(lines: lines)
    }

    /// The lines `align` compares: the moving band (fixed edges excluded), hashed exactly, or with
    /// noise tolerance once auto-scroll is on.
    private func comparable(_ next: Accepted, _ previous: Accepted) -> (previous: [LineHash], next: [LineHash]) {
        // Before any edges are known, use the edges this pair shares, capped so repetitive
        // content that happens to line up can't hide the whole frame.
        let length = next.hashes.count
        var band = edgesKnown ? edges : FixedEdgeDetector.detect(lineHashes: [previous.hashes, next.hashes])
        band.leading = min(band.leading, length / 3)
        band.trailing = min(band.trailing, length / 3)
        let range = band.leading..<(length - band.trailing)
        guard autoScrolled else { return (Array(previous.hashes[range]), Array(next.hashes[range])) }
        let (old, new) = LineProfiles.classify(previous.profiles, next.profiles)
        return (Array(old[range]), Array(new[range]))
    }

    /// Aligns `next` against `previous`, `posted` auto-scroll pixels further on (nil if unknown).
    private func align(_ next: Accepted, to previous: Accepted,
                       posted: Int?) -> (alignment: FrameAligner.Alignment, evidence: FrameAligner.Evidence?) {
        let lines = comparable(next, previous)
        // Vision aliases on repeating rows; with a measured step it never gets a say.
        let usesVision = aligner.usesVision && measuredScale == nil
        let axis = axis
        let hint = {
            usesVision ? FrameAligner.visionOffset(previous: previous.image, next: next.image, axis: axis) : nil
        }
        let prior = FrameAligner.Prior(expectedStep: posted,
                                       measuredOffsets: gauge.predictedOffsets(posted: posted, unit: stepUnit))
        return aligner.decide(previous: lines.previous, next: lines.next, hint: hint, prior: prior)
    }

    /// Appends the strip `next` reveals beyond `previous`, `offset` lines further on.
    private func appendStrip(of next: Accepted, offset: Int, after previous: Accepted) -> AppendOutcome {
        guard let first else { return .unrelated }
        let accepted = next.moved(to: previous.position + offset)
        narrowEdges(with: next.hashes, first: first.hashes, isSecond: !edgesKnown)
        edgesKnown = true
        let canvas = self.canvas ?? seedCanvas(with: first.frame)
        self.last = accepted

        // New lines: past what the canvas already holds, inside the moving (non-fixed) band.
        let length = next.frame.length(along: axis)
        let start = max(canvasEnd - accepted.position, edges.leading)
        let end = length - edges.trailing
        let room = maxLength - edges.trailing - canvas.length
        let count = max(0, min(end - start, room))
        if count > 0 {
            canvas.append(lines: start..<start + count, of: next.frame)
            canvasEnd = accepted.position + start + count
        }
        if canvas.length >= maxLength - edges.trailing {
            isFull = true
            return .maxLengthReached
        }
        return .appended(lines: count)
    }

    /// Appends a seam marker and the moving band of `gap`, which becomes the new anchor (returned,
    /// repositioned in content coordinates) along with the lines added. During auto-scroll, a `gap`
    /// that overlaps the last placed frame only adds what lies beyond the image's end (#112);
    /// otherwise all of it follows the seam.
    @discardableResult
    private func appendGap(_ gap: Accepted, posted: Int?) -> (accepted: Accepted, lines: Int) {
        guard let first, let previous = last else { return (gap, 0) }
        if !edgesKnown { edges = Self.solidEdges(previous.hashes, gap.hashes) }
        let canvas = self.canvas ?? seedCanvas(with: first.frame)
        let length = gap.frame.length(along: axis)
        let position: Int
        let start: Int
        let overlaps: Bool
        if let offset = overlap(of: gap, after: previous, posted: posted) {
            position = previous.position + offset
            start = max(canvasEnd - position, edges.leading)
            overlaps = true
        } else {
            // Content coordinates restart past everything so far.
            position = canvasEnd + length
            start = edges.leading
            overlaps = false
        }
        let anchor = gap.moved(to: position)
        last = anchor
        var room = maxLength - edges.trailing - canvas.length
        let count = max(0, min(length - edges.trailing - start, room - min(seamThickness, room)))
        if overlaps, count == 0 { return (anchor, 0) } // nothing new: no gap to mark
        let seam = min(seamThickness, room)
        canvas.appendSeam(lines: seam)
        room -= seam
        canvas.append(lines: start..<start + count, of: gap.frame)
        canvasEnd = position + start + count
        if canvas.length >= maxLength - edges.trailing { isFull = true }
        return (anchor, seam + count)
    }

    /// The stitched image so far, for live preview. Nil before the first frame.
    public func currentImage() -> CGImage? { compose() }

    /// True while a frame is held back (see the type notes); `finish()` would keep it after a seam.
    public var hasHeldFrame: Bool { pending != nil }

    /// The final stitched image, header once at the start and footer once at the end.
    /// A frame still held back (the user stopped right after a fast scroll) is kept after a seam.
    public func finish() -> CGImage? {
        if let held = pending, !isFull {
            pending = nil
            appendGap(held.frame, posted: held.posted)
        }
        return compose()
    }

    /// Clears all frames to start a new capture.
    public func reset() {
        first = nil
        last = nil
        pending = nil
        gauge = StepGauge()
        autoScrolled = false
        expectedStep = nil
        stepUnit = nil
        edges = .none
        edgesKnown = false
        canvas = nil
        canvasEnd = 0
        isFull = false
    }

    /// Fixed edges can only shrink: a line is fixed if it matches the first frame in every frame.
    private func narrowEdges(with hashes: [LineHash], first: [LineHash], isSecond: Bool) {
        let pair = FixedEdgeDetector.detect(lineHashes: [first, hashes])
        edges = isSecond ? pair : FixedEdges(
            leading: min(edges.leading, pair.leading), trailing: min(edges.trailing, pair.trailing)
        )
    }

    /// Copies the first frame (minus its trailing edge) onto a new canvas.
    private func seedCanvas(with frame: PixelFrame) -> GrowingCanvas {
        let canvas = GrowingCanvas(axis: axis, breadth: frame.breadth(along: axis),
                                   colorSpace: frame.context.colorSpace, maxLength: maxLength)
        let count = min(frame.length(along: axis) - edges.trailing, maxLength - edges.trailing)
        canvas.append(lines: 0..<max(0, count), of: frame)
        canvasEnd = canvas.length
        self.canvas = canvas
        return canvas
    }

    private func compose() -> CGImage? {
        guard let canvas, let last else { return first?.image }
        let length = last.frame.length(along: axis)
        return canvas.makeImage(appending: (length - edges.trailing)..<length, of: last.frame)
    }
}

extension Stitcher {
    /// Where `gap` overlaps `previous` during auto-scroll, so it isn't appended twice: the offset
    /// the measured step predicts if the frames match there, else the smallest offset where they
    /// match, the largest overlap (the next strip then starts after the last stitched row, never
    /// before it: rows may be missing at the seam, but none repeat). Nil when they don't overlap,
    /// or scrolling by hand.
    private func overlap(of gap: Accepted, after previous: Accepted, posted: Int?) -> Int? {
        guard posted != nil else { return nil }
        let lines = comparable(gap, previous)
        let minimumOverlap = max(FrameAligner.minimumOverlapLines,
                                 Int(Double(lines.next.count) * aligner.minimumOverlapFraction))
        let last = lines.next.count - minimumOverlap
        guard last >= 1 else { return nil }
        return aligner.firstMatch(previous: lines.previous, next: lines.next,
                                  among: gauge.predictedOffsets(posted: posted, unit: stepUnit) + Array(1...last))
    }

    /// Edges two unrelated frames share, cut back to their last line with detail: a real header
    /// or footer has some, while blank space matching by chance has none.
    static func solidEdges(_ one: [LineHash], _ other: [LineHash]) -> FixedEdges {
        let pair = FixedEdgeDetector.detect(lineHashes: [one, other])
        let count = one.count
        let leading = (0..<pair.leading).last { one[$0].isInformative }.map { $0 + 1 } ?? 0
        let trailing = ((count - pair.trailing)..<count).first { one[$0].isInformative }.map { count - $0 } ?? 0
        return FixedEdges(leading: leading, trailing: trailing)
    }
}

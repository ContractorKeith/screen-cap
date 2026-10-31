// Stitches scrolled frames into one long image (PLAN §5.4 steps 3–5).
import CoreGraphics

/// Builds a long screenshot from frames of a scrolling region.
///
/// Works in pixels; `scale` is metadata for the caller (1 or 2 for Retina). Each frame is
/// aligned against the last accepted one, still frames are dropped, sticky edges are trimmed
/// and only the newly revealed strip is appended. The leading edge (header) is kept once at
/// the start, the trailing edge (footer) once at the end.
///
/// A frame that doesn't overlap the last one is held back. If the next frame doesn't overlap
/// the last one either, the content really jumped (scrolled faster than one region per frame):
/// the held frame is appended whole after a dashed seam marker, reported as `.gapDetected`, and
/// stitching continues from it. If the next frame does overlap, the held one was a transient
/// (animation, lazy load) and is dropped.
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
    /// Auto-scroll step in pixels, if auto-scrolling. Breaks ties on repetitive content.
    public private(set) var expectedStep: Int?

    private struct Accepted {
        let image: CGImage
        let frame: PixelFrame
        let hashes: [LineHash]
        /// Content coordinate of the frame's line 0 (the first frame is at 0).
        let position: Int
    }

    private var first: Accepted?
    private var last: Accepted?
    /// A frame that didn't overlap `last`, waiting to see whether the content jumped.
    private var pending: Accepted?
    /// The offset accepted for the previous frame pair.
    private var previousStep: Int?
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

    /// Sets the auto-scroll step in pixels (nil while scrolling manually).
    public func setExpectedStep(_ step: Int?) {
        expectedStep = step
    }

    /// Lines in a gap's seam marker.
    var seamThickness: Int { max(2, Int((2 * scale).rounded())) }

    /// Aligns `frame` and appends its new strip.
    @discardableResult
    public func append(frame image: CGImage) -> AppendOutcome {
        guard let first, let last else {
            guard let frame = PixelFrame(image: image) else { return .unrelated }
            let seed = Accepted(image: image, frame: frame, hashes: frame.lineHashes(along: axis), position: 0)
            self.first = seed
            self.last = seed
            return .started
        }
        guard !isFull else { return .maxLengthReached }
        guard image.width == first.frame.width, image.height == first.frame.height,
              let frame = PixelFrame(image: image, colorSpace: first.frame.context.colorSpace) else {
            return .unrelated
        }
        let hashes = frame.lineHashes(along: axis)
        let next = Accepted(image: image, frame: frame, hashes: hashes, position: 0)

        switch align(next, to: last) {
        case .noMovement:
            pending = nil
            return .noMovement
        case .offset(let offset):
            pending = nil
            return appendStrip(of: next, offset: offset, after: last)
        case .unrelated:
            guard let gap = pending else {
                pending = next
                return .unrelated
            }
            pending = nil
            return appendJump(held: gap, then: next)
        }
    }

    /// Two frames in a row past `last`: the content jumped. Keeps the held frame after a seam,
    /// then appends what `next` adds beyond it.
    private func appendJump(held gap: Accepted, then next: Accepted) -> AppendOutcome {
        let anchor = appendGap(gap)
        var lines = anchor.lines
        if isFull { return .maxLengthReached }
        switch align(next, to: anchor.accepted) {
        case .offset(let offset):
            let outcome = appendStrip(of: next, offset: offset, after: anchor.accepted)
            guard case .appended(let added) = outcome else { return outcome }
            lines += added
        case .noMovement:
            break
        case .unrelated:
            pending = next
        }
        return .gapDetected(lines: lines)
    }

    /// Aligns the moving band (fixed edges excluded) of `next` against `previous`.
    private func align(_ next: Accepted, to previous: Accepted) -> FrameAligner.Alignment {
        // Before any edges are known, use the edges this pair shares, capped so repetitive
        // content that happens to line up can't hide the whole frame.
        let length = next.hashes.count
        var band = edgesKnown ? edges : FixedEdgeDetector.detect(lineHashes: [previous.hashes, next.hashes])
        band.leading = min(band.leading, length / 3)
        band.trailing = min(band.trailing, length / 3)
        let range = band.leading..<(length - band.trailing)
        let hint = aligner.usesVision
            ? FrameAligner.visionOffset(previous: previous.image, next: next.image, axis: axis) : nil
        let prior = FrameAligner.Prior(expectedStep: expectedStep, previousStep: previousStep)
        return aligner.align(previous: Array(previous.hashes[range]), next: Array(next.hashes[range]),
                             hint: hint, prior: prior)
    }

    /// Appends the strip `next` reveals beyond `previous`, `offset` lines further on.
    private func appendStrip(of next: Accepted, offset: Int, after previous: Accepted) -> AppendOutcome {
        guard let first else { return .unrelated }
        let accepted = Accepted(image: next.image, frame: next.frame, hashes: next.hashes,
                                position: previous.position + offset)
        narrowEdges(with: next.hashes, first: first.hashes, isSecond: !edgesKnown)
        edgesKnown = true
        let canvas = self.canvas ?? seedCanvas(with: first.frame)
        self.last = accepted
        previousStep = offset

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

    /// Appends a seam marker and the whole moving band of `gap`, which becomes the new anchor
    /// (returned, repositioned in content coordinates) along with the lines added.
    private func appendGap(_ gap: Accepted) -> (accepted: Accepted, lines: Int) {
        guard let first, let previous = last else { return (gap, 0) }
        if !edgesKnown { edges = Self.solidEdges(previous.hashes, gap.hashes) }
        let canvas = self.canvas ?? seedCanvas(with: first.frame)
        let length = gap.frame.length(along: axis)
        var room = maxLength - edges.trailing - canvas.length
        let seam = min(seamThickness, room)
        canvas.appendSeam(lines: seam)
        room -= seam
        let start = edges.leading
        let count = max(0, min(length - edges.trailing - start, room))
        canvas.append(lines: start..<start + count, of: gap.frame)
        // Content coordinates restart past everything so far; the canvas ends at the gap's band.
        let position = canvasEnd + length
        canvasEnd = position + start + count
        let anchor = Accepted(image: gap.image, frame: gap.frame, hashes: gap.hashes, position: position)
        last = anchor
        previousStep = nil
        if canvas.length >= maxLength - edges.trailing { isFull = true }
        return (anchor, seam + count)
    }

    /// The stitched image so far, for live preview. Nil before the first frame.
    public func currentImage() -> CGImage? { compose() }

    /// The final stitched image, header once at the start and footer once at the end.
    public func finish() -> CGImage? { compose() }

    /// Clears all frames to start a new capture.
    public func reset() {
        first = nil
        last = nil
        pending = nil
        previousStep = nil
        edges = .none
        edgesKnown = false
        canvas = nil
        canvasEnd = 0
        isFull = false
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

/// An RGBA bitmap that grows along the scroll axis in doubling chunks, so appending stays
/// linear overall instead of copying the whole image on every frame.
final class GrowingCanvas {
    let axis: ScrollAxis
    let breadth: Int
    let colorSpace: CGColorSpace
    let maxLength: Int
    private(set) var length = 0
    private var storage: PixelFrame?

    init(axis: ScrollAxis, breadth: Int, colorSpace: CGColorSpace?, maxLength: Int) {
        self.axis = axis
        self.breadth = breadth
        self.colorSpace = colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        self.maxLength = maxLength
    }

    private var capacity: Int { storage?.length(along: axis) ?? 0 }

    /// Copies `lines` of `frame` onto the end of the canvas.
    func append(lines: Range<Int>, of frame: PixelFrame) {
        guard !lines.isEmpty else { return }
        reserve(length + lines.count)
        guard let storage else { return }
        frame.copyLines(lines, along: axis, to: storage, at: length)
        length += lines.count
    }

    /// Appends `lines` lines of a dashed red-and-white seam marking a gap in the content.
    func appendSeam(lines: Int) {
        guard lines > 0 else { return }
        reserve(length + lines)
        guard let storage else { return }
        let red = UInt32(230) | UInt32(40) << 8 | UInt32(40) << 16 | 0xff00_0000
        let white = UInt32(0xffff_ffff)
        let rowPixels = storage.bytesPerRow / 4
        let base = storage.pixels
        let dash = max(4, lines * 3)
        for line in length..<length + lines {
            for index in 0..<breadth {
                let color = (index / dash).isMultiple(of: 2) ? red : white
                switch axis {
                case .vertical: base[line * rowPixels + index] = color
                case .horizontal: base[index * rowPixels + line] = color
                }
            }
        }
        length += lines
    }

    /// The canvas content followed by `extra` lines of `frame`, as a new image.
    func makeImage(appending extra: Range<Int>, of frame: PixelFrame) -> CGImage? {
        guard let output = makeBitmap(length: length + extra.count) else { return nil }
        if let storage {
            storage.copyLines(0..<length, along: axis, to: output, at: 0)
        }
        frame.copyLines(extra, along: axis, to: output, at: length)
        return output.context.makeImage()
    }

    /// Grows storage to hold at least `needed` lines, doubling (min 1024 lines) up to `maxLength`.
    private func reserve(_ needed: Int) {
        guard needed > capacity else { return }
        let target = min(max(needed, capacity * 2, 1024), max(needed, maxLength))
        guard let grown = makeBitmap(length: target) else { return }
        if let storage {
            storage.copyLines(0..<length, along: axis, to: grown, at: 0)
        }
        storage = grown
    }

    private func makeBitmap(length: Int) -> PixelFrame? {
        axis == .vertical
            ? PixelFrame(width: breadth, height: length, colorSpace: colorSpace)
            : PixelFrame(width: length, height: breadth, colorSpace: colorSpace)
    }
}

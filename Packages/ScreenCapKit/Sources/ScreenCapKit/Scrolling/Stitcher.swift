// Stitches scrolled frames into one long image (PLAN §5.4 steps 3–5).
import CoreGraphics

/// Builds a long screenshot from frames of a scrolling region.
///
/// Works in pixels; `scale` is metadata for the caller (1 or 2 for Retina). Each frame is
/// aligned against the last accepted one, still frames are dropped, sticky edges are trimmed
/// and only the newly revealed strip is appended. The leading edge (header) is kept once at
/// the start, the trailing edge (footer) once at the end.
public actor Stitcher {
    /// What happened to one appended frame.
    public enum AppendOutcome: Equatable, Sendable {
        /// The first frame; it seeds the canvas.
        case started
        /// Content moved; this many new lines were added (0 if the strip was all fixed edge).
        case appended(lines: Int)
        /// Same content as the last accepted frame; dropped.
        case noMovement
        /// Could not be aligned (different size, animation, a jump); dropped.
        case unrelated
        /// The `maxLength` cap is reached; nothing more is added.
        case maxLengthReached
    }

    public let axis: ScrollAxis
    /// Pixels per point of the source display. Metadata only.
    public let scale: CGFloat
    /// Cap on the stitched length along `axis`, in pixels, footer included.
    public let maxLength: Int
    private let aligner: FrameAligner

    private struct Accepted {
        let image: CGImage
        let frame: PixelFrame
        let hashes: [LineHash]
        /// Content coordinate of the frame's line 0 (the first frame is at 0).
        let position: Int
    }

    private var first: Accepted?
    private var last: Accepted?
    private var edges = FixedEdges.none
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
        let hint = aligner.usesVision ? FrameAligner.visionOffset(previous: last.image, next: image, axis: axis) : nil
        let offset: Int
        switch aligner.align(previous: last.hashes, next: hashes, hint: hint) {
        case .noMovement: return .noMovement
        case .unrelated: return .unrelated
        case .offset(let value): offset = value
        }

        let accepted = Accepted(image: image, frame: frame, hashes: hashes, position: last.position + offset)
        narrowEdges(with: hashes, first: first.hashes, isSecond: canvas == nil)
        let canvas = self.canvas ?? seedCanvas(with: first.frame)
        self.last = accepted

        // New lines: past what the canvas already holds, inside the moving (non-fixed) band.
        let length = frame.length(along: axis)
        let start = max(canvasEnd - accepted.position, edges.leading)
        let end = length - edges.trailing
        let room = maxLength - edges.trailing - canvas.length
        let count = max(0, min(end - start, room))
        if count > 0 {
            canvas.append(lines: start..<start + count, of: frame)
            canvasEnd = accepted.position + start + count
        }
        if canvas.length >= maxLength - edges.trailing {
            isFull = true
            return .maxLengthReached
        }
        return .appended(lines: count)
    }

    /// The stitched image so far, for live preview. Nil before the first frame.
    public func currentImage() -> CGImage? { compose() }

    /// The final stitched image, header once at the start and footer once at the end.
    public func finish() -> CGImage? { compose() }

    /// Clears all frames to start a new capture.
    public func reset() {
        first = nil
        last = nil
        edges = .none
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

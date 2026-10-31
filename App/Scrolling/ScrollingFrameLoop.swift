import CoreGraphics
import ScreenCapKit

/// One frame of a scrolling capture at a time, in the order auto-scroll needs (#98):
/// capture and stitch the frame, let the caller record it, and only then post the next step.
/// So the first frame shows the region before anything moved, and every frame is one known step on.
///
/// The end of the content needs evidence: still frames (byte-identical to the one before, or found
/// in place by the stitcher, which a blinking cursor or fading scroll bar still allows), confirmed
/// by a probe that scrolls back one step and returns to the same place. A frame that changed but
/// couldn't be placed (repeating rows) is progress, never the end.
@MainActor
final class ScrollingFrameLoop {
    struct Frame: Equatable {
        let outcome: Stitcher.AppendOutcome
        /// The content moved: pixels differ from the previous frame's and not just in place.
        let changed: Bool
    }

    let collector: ScrollingFrameCollector
    let scroller: AutoScroller
    /// How long the page gets to redraw after a probe scroll.
    let settle: Duration
    /// Unchanged frames in a row.
    private var stillFrames = 0
    /// Points posted since the last frame the stitcher placed: frames the page hadn't redrawn for
    /// yet, or that were held back, still sit between it and the next one.
    private var unplacedDistance = 0

    init(collector: ScrollingFrameCollector, scroller: AutoScroller, settle: Duration) {
        self.collector = collector
        self.scroller = scroller
        self.settle = settle
    }

    /// Captures and stitches one frame and hands it to `record`, which returns whether the capture
    /// goes on; if it does and auto-scroll is on, posts the next step. Nil when the capture failed.
    func next(record: (Frame) -> Bool) async -> Frame? {
        guard let frame = await capture() else { return nil }
        if record(frame) { scroller.advance() }
        return frame
    }

    private func capture() async -> Frame? {
        let scrolling = scroller.state == .scrolling
        unplacedDistance = scrolling ? unplacedDistance + scroller.takePostedDistance() : 0
        guard let outcome = await grab() else { return nil }
        var frame = Frame(outcome: outcome, changed: moved(outcome))
        stillFrames = frame.changed ? 0 : stillFrames + 1
        if scrolling, stillFrames >= ScrollingSession.stillFramesToEnd, outcome != .maxLengthReached {
            switch await probe() {
            case nil: return nil
            case .end?: break
            case let .moved(later)?:
                frame = later
                stillFrames = 0
            }
        }
        return frame
    }

    private enum Probe {
        /// The page is at the end of its content.
        case end
        /// The page was still moving (it redrew late); this frame was taken after the probe.
        case moved(Frame)
    }

    /// Scrolls back one step and returns. Nil when a capture failed.
    private func probe() async -> Probe? {
        scroller.nudge(by: -scroller.step)
        try? await Task.sleep(for: settle)
        guard let wentBack = await collector.peekChanged() else { return nil }
        scroller.nudge(by: scroller.step)
        try? await Task.sleep(for: settle)
        // Didn't move back either: the page doesn't scroll any further, whichever way.
        guard wentBack else { return .end }
        guard let outcome = await grab() else { return nil }
        return moved(outcome) ? .moved(Frame(outcome: outcome, changed: true)) : .end
    }

    private func moved(_ outcome: Stitcher.AppendOutcome) -> Bool {
        collector.lastFrameChanged && outcome != .noMovement
    }

    private func grab() async -> Stitcher.AppendOutcome? {
        let distance = unplacedDistance
        let step = scroller.step
        let outcome = await collector.grab { scale in
            guard distance > 0 else { return nil }
            return (Int((CGFloat(distance) * scale).rounded()), Int((CGFloat(step) * scale).rounded()))
        }
        switch outcome {
        case .started, .appended, .gapDetected: unplacedDistance = 0
        default: break
        }
        return outcome
    }
}

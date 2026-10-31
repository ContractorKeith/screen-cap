// Auto-scroll for scrolling capture (PLAN §5.4 step 6).
import ApplicationServices
import CoreGraphics

/// Posts scroll-wheel events. Injected so the scroller can be tested without moving anything.
@MainActor
public protocol ScrollEventPosting {
    /// Whether the app may post events (Accessibility permission).
    var isTrusted: Bool { get }
    /// Scrolls content at `point` (global display coordinates) by `delta` pixels.
    /// Positive `delta` reveals content further down (vertical) or right (horizontal).
    func postScroll(at point: CGPoint, axis: ScrollAxis, delta: Int)
}

/// Real event poster: `AXIsProcessTrusted()` plus pixel-unit `CGEvent` scroll wheels.
public struct SystemScrollEventPoster: ScrollEventPosting {
    public init() {}

    public var isTrusted: Bool { AXIsProcessTrusted() }

    public func postScroll(at point: CGPoint, axis: ScrollAxis, delta: Int) {
        // Negative wheel values scroll toward the end of the content.
        let amount = Int32(clamping: -delta)
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
            wheel1: axis == .vertical ? amount : 0, wheel2: axis == .horizontal ? amount : 0, wheel3: 0
        ) else { return }
        event.location = point
        event.post(tap: .cghidEventTap)
    }
}

/// When auto-scroll should stop, given stitcher outcomes. Pure, so it is unit-tested.
///
/// The end of the content needs real evidence: consecutive frames where the content didn't move
/// (`frameChanged: false`: byte-identical, or found in place). A frame whose content changed is
/// progress even when the stitcher could not place it (repeating rows), so it never counts toward
/// the end (#98).
public struct AutoScrollStopRule: Equatable, Sendable {
    /// Consecutive still frames that mean the end of the content was reached.
    public var noMovementLimit: Int
    private var stillFrames = 0

    public init(noMovementLimit: Int = 2) {
        self.noMovementLimit = noMovementLimit
    }

    /// Feeds one outcome; returns a reason when scrolling should stop. `frameChanged` says whether
    /// the content moved since the previous frame; nil falls back to the outcome alone.
    public mutating func record(_ outcome: Stitcher.AppendOutcome,
                                frameChanged: Bool? = nil) -> AutoScroller.StopReason? {
        if outcome == .maxLengthReached { return .maxLengthReached }
        if let frameChanged {
            guard !frameChanged, outcome != .started else {
                stillFrames = 0
                return nil
            }
            stillFrames += 1
            return stillFrames >= noMovementLimit ? .endReached : nil
        }
        switch outcome {
        case .noMovement:
            stillFrames += 1
            return stillFrames >= noMovementLimit ? .endReached : nil
        case .started, .appended, .gapDetected, .maxLengthReached:
            stillFrames = 0
            return nil
        case .unrelated, .ambiguous:
            return nil // held back; neither progress nor the end
        }
    }
}

/// Scrolls a region one step at a time, in lockstep with the frames.
///
/// `start(at:)` only arms it: nothing is posted until the caller has captured a frame and calls
/// `advance()`, so the first frame always shows the region as the user left it (#98). Each frame
/// is followed by one step, so the distance posted per frame is known. Scrolling stops at the
/// end of the content, at the length cap or on `cancel()`.
@MainActor
public final class AutoScroller {
    public enum StopReason: Equatable, Sendable {
        case endReached
        case maxLengthReached
        case cancelled
    }

    public enum State: Equatable, Sendable {
        case idle
        case scrolling
        /// Accessibility permission is missing; no events were posted.
        case needsAccessibility
        case stopped(StopReason)
    }

    public private(set) var state: State = .idle
    public let axis: ScrollAxis
    /// Points per scroll step. Keep well under the region length so frames overlap.
    public let step: Int
    private let poster: any ScrollEventPosting
    private var rule = AutoScrollStopRule()
    private var point = CGPoint.zero
    /// Points posted since the last `takePostedDistance()`.
    private var posted = 0

    public init(axis: ScrollAxis = .vertical, step: Int = 120,
                poster: any ScrollEventPosting = SystemScrollEventPoster()) {
        self.axis = axis
        self.step = step
        self.poster = poster
    }

    /// Arms auto-scroll at `point` without posting anything. Reports `.needsAccessibility` if the
    /// app is not trusted.
    @discardableResult
    public func start(at point: CGPoint) -> State {
        guard state != .scrolling else { return state }
        guard poster.isTrusted else {
            state = .needsAccessibility
            return state
        }
        rule = AutoScrollStopRule()
        posted = 0
        self.point = point
        state = .scrolling
        return state
    }

    /// Posts one step toward the end of the content. Call after each frame is captured.
    public func advance() {
        guard state == .scrolling else { return }
        poster.postScroll(at: point, axis: axis, delta: step)
        posted += step
    }

    /// Posts `delta` points without counting them as progress: an end-of-content probe scrolls
    /// back one step and returns, which cancels out.
    public func nudge(by delta: Int) {
        guard state == .scrolling else { return }
        poster.postScroll(at: point, axis: axis, delta: delta)
    }

    /// Points scrolled forward since the last call.
    public func takePostedDistance() -> Int {
        defer { posted = 0 }
        return posted
    }

    /// Feeds a stitcher outcome; stops scrolling when a stop condition is met.
    public func record(_ outcome: Stitcher.AppendOutcome, frameChanged: Bool? = nil) {
        guard state == .scrolling, let reason = rule.record(outcome, frameChanged: frameChanged) else { return }
        state = .stopped(reason)
    }

    /// Stops scrolling (Esc).
    public func cancel() {
        guard state == .scrolling else { return }
        state = .stopped(.cancelled)
    }
}

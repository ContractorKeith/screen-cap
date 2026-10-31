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
public struct AutoScrollStopRule: Equatable, Sendable {
    /// Consecutive still frames that mean the end of the content was reached.
    public var noMovementLimit: Int
    private var stillFrames = 0

    public init(noMovementLimit: Int = 2) {
        self.noMovementLimit = noMovementLimit
    }

    /// Feeds one outcome; returns a reason when scrolling should stop.
    public mutating func record(_ outcome: Stitcher.AppendOutcome) -> AutoScroller.StopReason? {
        switch outcome {
        case .noMovement:
            stillFrames += 1
            return stillFrames >= noMovementLimit ? .endReached : nil
        case .maxLengthReached:
            return .maxLengthReached
        case .started, .appended:
            stillFrames = 0
            return nil
        case .unrelated:
            return nil // a transient (animation, lazy load); neither progress nor the end
        }
    }
}

/// Scrolls a region step by step while the capture pipeline feeds frames to a `Stitcher`.
///
/// The caller grabs a frame after each step, appends it to the stitcher and passes the
/// outcome to `record(_:)`. Scrolling stops at the end of the content, at the length cap or
/// on `cancel()`.
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
    /// Pixels per scroll step. Keep well under the region length so frames overlap.
    public let step: Int
    public let interval: Duration
    private let poster: any ScrollEventPosting
    private var rule = AutoScrollStopRule()
    private var task: Task<Void, Never>?

    public init(axis: ScrollAxis = .vertical, step: Int = 120, interval: Duration = .milliseconds(150),
                poster: any ScrollEventPosting = SystemScrollEventPoster()) {
        self.axis = axis
        self.step = step
        self.interval = interval
        self.poster = poster
    }

    /// Starts posting scroll events at `point`. Reports `.needsAccessibility` without posting
    /// if the app is not trusted.
    @discardableResult
    public func start(at point: CGPoint) -> State {
        guard state != .scrolling else { return state }
        guard poster.isTrusted else {
            state = .needsAccessibility
            return state
        }
        rule = AutoScrollStopRule()
        state = .scrolling
        task = Task { [weak self] in
            while let self, self.state == .scrolling, !Task.isCancelled {
                self.poster.postScroll(at: point, axis: self.axis, delta: self.step)
                try? await Task.sleep(for: self.interval)
            }
        }
        return state
    }

    /// Feeds a stitcher outcome; stops scrolling when a stop condition is met.
    public func record(_ outcome: Stitcher.AppendOutcome) {
        guard state == .scrolling, let reason = rule.record(outcome) else { return }
        stop(reason)
    }

    /// Stops scrolling (Esc).
    public func cancel() {
        guard state == .scrolling else { return }
        stop(.cancelled)
    }

    private func stop(_ reason: StopReason) {
        state = .stopped(reason)
        task?.cancel()
        task = nil
    }
}

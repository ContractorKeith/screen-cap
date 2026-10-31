import CoreGraphics
import ScreenCapKit

/// What a finished two-finger swipe on a panel does.
enum SwipeAction: Equatable {
    /// Swiped away from the side edge the stack docks against.
    case dismiss
    /// Swiped toward that edge.
    case save
}

/// Turns trackpad scroll deltas into a swipe decision. Pure, so it is unit-tested.
enum SwipeClassifier {
    /// Horizontal finger travel, in points, needed before a swipe counts.
    static let threshold: CGFloat = 60

    /// Physical finger movement (+ = right / up) from a scroll event's delta.
    /// With natural scrolling the delta already follows the fingers; otherwise it is reversed.
    static func fingerDelta(_ scrollingDelta: CGFloat, invertedFromDevice: Bool) -> CGFloat {
        invertedFromDevice ? scrollingDelta : -scrollingDelta
    }

    /// The action for a completed swipe, or nil if it was too short or mostly vertical.
    static func action(fingerDX: CGFloat, fingerDY: CGFloat, corner: ScreenCorner,
                       threshold: CGFloat = threshold) -> SwipeAction? {
        guard abs(fingerDX) >= threshold, abs(fingerDX) > abs(fingerDY) else { return nil }
        let towardEdge = corner.isLeft ? fingerDX < 0 : fingerDX > 0
        return towardEdge ? .save : .dismiss
    }
}

/// Accumulates one scroll gesture between its `began` and `ended` phases.
struct SwipeTracker: Equatable {
    private(set) var dx: CGFloat = 0
    private(set) var dy: CGFloat = 0

    mutating func add(dx: CGFloat, dy: CGFloat) {
        self.dx += dx
        self.dy += dy
    }

    func action(for corner: ScreenCorner) -> SwipeAction? {
        SwipeClassifier.action(fingerDX: dx, fingerDY: dy, corner: corner)
    }
}

/// Turns one scroll event's phases into swipe steps (#88). Only a gesture that ends normally
/// (`.ended`) is handed on for a decision; a cancelled one is discarded so the panel snaps back.
/// Momentum events (after the fingers lift) and plain mouse wheels never move or commit.
struct SwipeGesture {
    /// The parts of an `NSEvent` the gesture reads, so tests can feed synthetic sequences.
    struct Phase: OptionSet {
        let rawValue: Int
        static let began = Phase(rawValue: 1 << 0)
        static let changed = Phase(rawValue: 1 << 1)
        static let ended = Phase(rawValue: 1 << 2)
        static let cancelled = Phase(rawValue: 1 << 3)
        static let mayBegin = Phase(rawValue: 1 << 4)
    }

    enum Step: Equatable {
        /// Finger travel so far, for the panel to follow.
        case moved(CGFloat)
        /// Finished normally; the tracker decides save, dismiss or nothing.
        case ended(SwipeTracker)
        /// Cancelled by the system: restore the panel, do nothing else.
        case cancelled
    }

    private var tracker: SwipeTracker?

    /// Feeds one event. `phase` empty = not a gesture (mouse wheel); `isMomentum` = momentum phase.
    /// Deltas are finger movement (already corrected for natural scrolling).
    mutating func handle(phase: Phase, isMomentum: Bool, dx: CGFloat, dy: CGFloat) -> [Step] {
        guard !isMomentum, !phase.isEmpty else { return [] }
        var steps: [Step] = []
        if phase.contains(.began) || tracker == nil { tracker = SwipeTracker() }
        if phase.contains(.changed) {
            tracker?.add(dx: dx, dy: dy)
            steps.append(.moved(tracker?.dx ?? 0))
        }
        if phase.contains(.cancelled) {
            tracker = nil
            steps.append(.cancelled)
        } else if phase.contains(.ended), let finished = tracker {
            tracker = nil
            steps.append(.ended(finished))
        }
        return steps
    }
}

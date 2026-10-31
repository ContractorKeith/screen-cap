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

import Foundation

/// Countdown for a panel's auto-close, paused while the pointer is over it.
/// Pure value type driven by explicit dates so tests don't wait on a clock.
struct AutoCloseTimer: Equatable {
    /// Full length in seconds; nil means the panel never closes on its own.
    let duration: TimeInterval?
    /// Time left as of `runningSince` (or now, if paused).
    private var banked: TimeInterval?
    /// When the countdown last resumed; nil while paused.
    private var runningSince: Date?

    init(seconds: Int?, now: Date) {
        duration = seconds.map { TimeInterval(max($0, 1)) }
        banked = duration
        runningSince = now
    }

    var isPaused: Bool { runningSince == nil }

    /// Seconds left at `now`; nil when there is no auto-close.
    func remaining(at now: Date) -> TimeInterval? {
        guard let banked else { return nil }
        guard let runningSince else { return banked }
        return max(0, banked - now.timeIntervalSince(runningSince))
    }

    func isExpired(at now: Date) -> Bool {
        remaining(at: now).map { $0 <= 0 } ?? false
    }

    mutating func pause(at now: Date) {
        guard !isPaused else { return }
        banked = remaining(at: now)
        runningSince = nil
    }

    mutating func resume(at now: Date) {
        guard isPaused else { return }
        runningSince = now
    }

    /// Starts over from the full length, e.g. after the user interacts with the panel.
    mutating func restart(at now: Date) {
        banked = duration
        runningSince = now
    }
}

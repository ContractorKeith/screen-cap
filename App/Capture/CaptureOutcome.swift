import Foundation

/// How one capture request ended. `--quit` turns it into the process exit status.
enum CaptureOutcome: Equatable {
    /// At least one image reached its after-capture action (or OCR finished) and nothing failed.
    case delivered
    /// The user cancelled, or the flow ended without an image.
    case cancelled
    /// The capture, save, copy or OCR failed.
    case failed(String)
    /// The request never ran (no permission, another capture busy, bad arguments).
    case notStarted(String)

    /// Exit status for `--quit`: 0 delivered, 1 failed, 2 cancelled, 3 not started.
    var exitStatus: Int32 {
        switch self {
        case .delivered: 0
        case .failed: 1
        case .cancelled: 2
        case .notStarted: 3
        }
    }

    /// Why it didn't deliver, for the log.
    var reason: String {
        switch self {
        case .delivered: "delivered"
        case .cancelled: "cancelled or nothing captured"
        case let .failed(reason): "failed: \(reason)"
        case let .notStarted(reason): "not started: \(reason)"
        }
    }

    /// Folds a later event into this outcome. A failure sticks; a delivery beats "cancelled".
    func merged(with next: CaptureOutcome) -> CaptureOutcome {
        switch (self, next) {
        case (.failed, _), (.notStarted, _): self
        case (_, .failed), (_, .notStarted): next
        case (.delivered, _), (_, .delivered): .delivered
        default: .cancelled
        }
    }
}

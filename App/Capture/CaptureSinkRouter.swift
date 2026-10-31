import ScreenCapKit

/// Routes after-capture actions that need UI to the feature that owns them.
///
/// Features assign themselves in `AppDelegate.installFeatures()`; anything unassigned falls
/// back to saving, so the app stays usable while features land one PR at a time.
@MainActor
final class CaptureSinkRouter: CaptureSink {
    /// Quick Access overlay (issue #24).
    var overlay: CaptureSink?
    /// Annotate editor (issue #25).
    var annotate: CaptureSink?
    /// Pinned screenshots (issue #26).
    var pin: CaptureSink?
    private let fallback: CaptureSink

    init(fallback: CaptureSink) {
        self.fallback = fallback
    }

    func deliver(_ result: CaptureResult, action: AfterCaptureAction) async {
        let target: CaptureSink? = switch action {
        case .overlay: overlay
        case .annotate: annotate
        case .pin: pin
        case .copy, .save: nil
        }
        await (target ?? fallback).deliver(result, action: action)
    }
}

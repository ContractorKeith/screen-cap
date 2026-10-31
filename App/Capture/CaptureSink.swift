import Foundation
import ScreenCapKit

/// One finished capture at full resolution. The output scale is applied only when saving or copying.
struct CaptureResult: Sendable {
    let image: CapturedImage
    let kind: CaptureKind
    /// Front app and window title, for filename tokens.
    let context: FilenameTemplate.Context
    /// The history record, if the history write succeeded.
    var historyRecordID: UUID?
    /// The history copy's file, offered when a save fails.
    var historyFileURL: URL?
    /// History is on but couldn't store this capture, so closing it unsaved loses it (#113).
    var historyWriteFailed = false
}

/// Receives captures whose after-capture action needs UI: `.overlay`, `.annotate`, `.pin`.
///
/// Quick Access, the editor and pins plug in here; `.save` and `.copy` are handled by the coordinator.
@MainActor
protocol CaptureSink: AnyObject {
    func deliver(_ result: CaptureResult, action: AfterCaptureAction) async
}

/// Used until the UI features land: saves to the save folder and logs.
@MainActor
final class SavingCaptureSink: CaptureSink {
    private let output: CaptureOutput

    init(output: CaptureOutput) {
        self.output = output
    }

    func deliver(_ result: CaptureResult, action: AfterCaptureAction) async {
        do {
            let url = try await output.save(result)
            appLog.notice("No \(action.rawValue, privacy: .public) UI yet; saved \(url.path, privacy: .public)")
        } catch {
            appLog.error("Save failed: \(error.localizedDescription, privacy: .public)")
            CaptureFailureHUD.showOutputFailed(.save, error: error, result: result, output: output)
        }
    }
}

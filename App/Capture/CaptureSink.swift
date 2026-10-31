import Foundation
import ScreenCapKit

/// One finished capture, already scaled to the output scale setting.
struct CaptureResult: Sendable {
    let image: CapturedImage
    let kind: CaptureKind
    /// Front app and window title, for filename tokens.
    let context: FilenameTemplate.Context
    /// The history record, if the history write succeeded.
    var historyRecordID: UUID?
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
        }
    }
}

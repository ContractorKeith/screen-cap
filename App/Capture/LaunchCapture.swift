import AppKit
import ScreenCapKit

// `--capture <kind> [--quit]`: the same path as the shortcut, plus an exit status for scripts.
extension CaptureCoordinator {
    /// Runs the launch capture. With `--quit`, exits once it is fully delivered, non-zero if it wasn't.
    func runLaunchCapture(_ launch: LaunchArguments) {
        let summary = launch.capture?.rawValue ?? "invalid"
        appLog.notice("Launch capture: \(summary, privacy: .public)")
        let outcome: CaptureOutcome?
        let task: Task<Void, Never>?
        if !launch.problems.isEmpty {
            let problems = launch.problems.joined(separator: "; ")
            appLog.error("Launch arguments: \(problems, privacy: .public)")
            outcome = .notStarted(problems)
            task = nil
        } else if let kind = launch.capture {
            task = if kind == .window, let app = launch.windowApp {
                captureWindow(ofApp: app, action: launch.action)
            } else {
                capture(kind, action: launch.action)
            }
            outcome = task == nil ? lastOutcome ?? .notStarted("another capture is in progress") : nil
        } else {
            return
        }
        guard launch.quitAfterCapture else { return }
        Task {
            await task?.value
            Self.quit(with: outcome ?? lastOutcome ?? .cancelled)
        }
    }

    /// Terminates normally (so cleanup runs), then exits with the outcome's status.
    private static func quit(with outcome: CaptureOutcome) {
        let status = outcome.exitStatus
        if status == 0 {
            appLog.notice("--quit: capture delivered; exiting 0")
        } else {
            appLog.error("--quit: \(outcome.reason, privacy: .public); exiting \(status)")
            FileHandle.standardError.write(Data("ScreenCap: \(outcome.reason)\n".utf8))
        }
        // NSApp.terminate always exits 0; this observer runs after the delegate's cleanup.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: nil) { _ in exit(status) }
        NSApp.terminate(nil)
    }
}

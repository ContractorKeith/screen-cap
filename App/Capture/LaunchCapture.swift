import AppKit
import ScreenCapKit

// `--capture <kind> [--quit]`: the same path as the shortcut, plus an exit status for scripts.

/// What a launch does before any capture runs. Pure, so the exit decision is testable (#135).
enum LaunchStart: Equatable {
    case none
    /// Bad arguments: never starts a capture; with `--quit` it exits with this outcome's status (3).
    case refused(CaptureOutcome)
    case capture(CaptureKind)
}

extension LaunchArguments {
    var start: LaunchStart {
        if !problems.isEmpty { return .refused(.notStarted(problems.joined(separator: "; "))) }
        return capture.map(LaunchStart.capture) ?? .none
    }
}

extension CaptureCoordinator {
    /// Runs the launch capture. With `--quit`, exits once it is fully delivered, non-zero if it wasn't.
    func runLaunchCapture(_ launch: LaunchArguments) {
        let summary = launch.capture?.rawValue ?? "invalid"
        appLog.notice("Launch capture: \(summary, privacy: .public)")
        let outcome: CaptureOutcome?
        let task: Task<Void, Never>?
        for warning in launch.warnings {
            appLog.error("Launch arguments: \(warning, privacy: .public)")
            FileHandle.standardError.write(Data("ScreenCap: \(warning)\n".utf8))
        }
        switch launch.start {
        case let .refused(refusal):
            appLog.error("Launch arguments: \(refusal.reason, privacy: .public)")
            outcome = refusal
            task = nil
        case let .capture(kind):
            task = if kind == .window, let app = launch.windowApp {
                captureWindow(ofApp: app, action: launch.action)
            } else {
                capture(kind, action: launch.action)
            }
            outcome = task == nil ? lastOutcome ?? .notStarted("another capture is in progress") : nil
        case .none:
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

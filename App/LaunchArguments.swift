import ScreenCapKit

/// Hidden command-line options for automation and CI smoke tests:
/// `ScreenCap --capture <kind> [--action save|copy|overlay|annotate|pin] [--window <app>] [--quit]`.
/// `--window` skips the window picker and captures that app's frontmost window (name or bundle ID).
///
/// With `--quit` the process exits once the capture is fully delivered (OCR included), with
/// status 0 delivered, 1 failed, 2 cancelled, 3 not started (no permission or bad arguments).
struct LaunchArguments: Equatable {
    var capture: CaptureKind?
    var action: AfterCaptureAction?
    var windowApp: String?
    /// Quit once the capture is delivered.
    var quitAfterCapture = false
    /// Our own options given a missing or unknown value, e.g. `--capture bogus`.
    var problems: [String] = []

    /// Parses `CommandLine.arguments` (the first element, the executable, is skipped).
    /// Unknown options are ignored, so system-added arguments like `-NSDocumentRevisionsDebugMode` pass.
    /// A value that starts with `--` is never consumed, so `--capture --quit` still quits.
    static func parse(_ arguments: [String]) -> LaunchArguments {
        var result = LaunchArguments()
        var index = 1
        while index < arguments.count {
            let option = arguments[index]
            let next = index + 1 < arguments.count ? arguments[index + 1] : nil
            let value = next.flatMap { $0.hasPrefix("--") ? nil : $0 }
            if value != nil, ["--capture", "--action", "--window"].contains(option) { index += 1 }
            switch option {
            case "--capture":
                result.capture = value.flatMap(CaptureKind.init(rawValue:))
                if result.capture == nil {
                    result.problems.append("--capture needs a kind, got \(value ?? "nothing")")
                }
            case "--action":
                result.action = value.flatMap(AfterCaptureAction.init(rawValue:))
                if result.action == nil {
                    result.problems.append("--action needs an action, got \(value ?? "nothing")")
                }
            case "--window":
                result.windowApp = value
                if value == nil { result.problems.append("--window needs an app name") }
            case "--quit":
                result.quitAfterCapture = true
            default:
                break
            }
            index += 1
        }
        return result
    }

    /// True if the launch asked for an automated capture (valid or not).
    var requestsCapture: Bool { capture != nil || !problems.isEmpty }
}

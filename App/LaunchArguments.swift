import ScreenCapKit

/// Hidden command-line options for automation and CI smoke tests:
/// `ScreenCap --capture <kind> [--action save|copy|overlay|annotate|pin] [--window <app>] [--region x,y,w,h] [--quit]`.
/// `--window` skips the window picker and captures that app's frontmost window (name or bundle ID).
/// `--region` is read by `ScrollingLaunchOptions`; here it is only validated (#119): a bad value with
/// `--quit` is a usage error (exit 3, never the interactive overlay); without `--quit` it warns and
/// falls back to selecting interactively.
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
    /// Non-fatal notes for stderr, e.g. a bad `--region` without `--quit` falling back to the overlay.
    var warnings: [String] = []

    static let regionUsage = "--region must be x,y,w,h in plain decimals with a positive size"

    /// Parses `CommandLine.arguments` (the first element, the executable, is skipped).
    /// Unknown options are ignored, so system-added arguments like `-NSDocumentRevisionsDebugMode` pass.
    /// A value that starts with `--` is never consumed, so `--capture --quit` still quits.
    static func parse(_ arguments: [String]) -> LaunchArguments {
        var result = LaunchArguments()
        var badRegion: String? // kept until every option is read, since `--quit` may come later
        var index = 1
        while index < arguments.count {
            let option = arguments[index]
            let next = index + 1 < arguments.count ? arguments[index + 1] : nil
            let value = next.flatMap { $0.hasPrefix("--") ? nil : $0 }
            if value != nil, ["--capture", "--action", "--window", "--region"].contains(option) { index += 1 }
            result.apply(option, value: value, badRegion: &badRegion)
            index += 1
        }
        result.report(badRegion: badRegion)
        return result
    }

    private mutating func apply(_ option: String, value: String?, badRegion: inout String?) {
        switch option {
        case "--capture":
            capture = value.flatMap(CaptureKind.init(rawValue:))
            if capture == nil { problems.append("--capture needs a kind, got \(value ?? "nothing")") }
        case "--action":
            action = value.flatMap(AfterCaptureAction.init(rawValue:))
            if action == nil { problems.append("--action needs an action, got \(value ?? "nothing")") }
        case "--window":
            windowApp = value
            if value == nil { problems.append("--window needs an app name") }
        case "--region":
            badRegion = value.flatMap(ScrollingLaunchOptions.parseRect) == nil ? value ?? "nothing" : nil
        case "--quit":
            quitAfterCapture = true
        default:
            break
        }
    }

    /// #119: with `--quit` a bad region is a usage error; without it, warn and select interactively.
    private mutating func report(badRegion: String?) {
        guard let badRegion else { return }
        let message = "\(Self.regionUsage), got \(badRegion)"
        if quitAfterCapture {
            problems.append(message)
        } else {
            warnings.append("\(message); selecting the region interactively")
        }
    }

    /// True if the launch asked for an automated capture (valid or not).
    var requestsCapture: Bool { capture != nil || !problems.isEmpty }
}

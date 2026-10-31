import ScreenCapKit

/// Hidden command-line options for automation and CI smoke tests:
/// `ScreenCap --capture <kind> [--action save|copy|overlay|annotate|pin] [--window <app>] [--quit]`.
/// `--window` skips the window picker and captures that app's frontmost window (name or bundle ID).
struct LaunchArguments: Equatable {
    var capture: CaptureKind?
    var action: AfterCaptureAction?
    var windowApp: String?
    /// Quit once the capture is delivered.
    var quitAfterCapture = false

    /// Parses `CommandLine.arguments` (the first element, the executable, is skipped).
    /// Unknown options and values are ignored, so system-added arguments like `-NSDocumentRevisionsDebugMode` pass.
    static func parse(_ arguments: [String]) -> LaunchArguments {
        var result = LaunchArguments()
        var index = 1
        while index < arguments.count {
            let value = index + 1 < arguments.count ? arguments[index + 1] : nil
            switch arguments[index] {
            case "--capture":
                result.capture = value.flatMap(CaptureKind.init(rawValue:))
                index += 1
            case "--action":
                result.action = value.flatMap(AfterCaptureAction.init(rawValue:))
                index += 1
            case "--window":
                result.windowApp = value
                index += 1
            case "--quit":
                result.quitAfterCapture = true
            default:
                break
            }
            index += 1
        }
        return result
    }
}

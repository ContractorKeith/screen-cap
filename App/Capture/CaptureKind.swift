import Foundation
import ScreenCapKit

/// What the user asked to capture. Raw values are the `--capture` launch argument values.
///
/// Shadows ScreenCapKit's history `CaptureKind` inside the app (it can't be spelled here,
/// since the module has a same-named enum); history records use `filenameKind`'s raw value.
enum CaptureKind: String, CaseIterable, Sendable {
    case area, window, fullscreen, previousArea, selfTimer, allInOne, scrolling, text

    /// The settings key that holds this kind's after-capture action.
    var shortcut: CaptureShortcut {
        switch self {
        case .area, .allInOne, .text: .area
        case .window: .window
        case .fullscreen: .fullscreen
        case .previousArea: .previousArea
        case .selfTimer: .selfTimer
        case .scrolling: .scrolling
        }
    }

    /// Value for the `{kind}` filename token.
    var filenameKind: FilenameTemplate.Kind {
        switch self {
        case .window: .window
        case .fullscreen: .fullscreen
        case .scrolling: .scrolling
        case .area, .previousArea, .selfTimer, .allInOne, .text: .area
        }
    }
}

/// Requests for features other workers own. Posted on `NotificationCenter.default`.
extension Notification.Name {
    /// Scrolling capture of a region. userInfo: `rect` (NSValue, global AppKit points).
    static let scrollingCaptureRequested = Notification.Name("ScreenCapScrollingCaptureRequested")
    /// OCR of a region. userInfo: `rect` (NSValue, global AppKit points).
    static let captureTextRequested = Notification.Name("ScreenCapCaptureTextRequested")
    static let openHistoryRequested = Notification.Name("ScreenCapOpenHistoryRequested")
    static let toggleOverlaysRequested = Notification.Name("ScreenCapToggleOverlaysRequested")
}

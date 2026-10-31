import Foundation

/// Requests Quick Access sends to features it doesn't own, and receives from the menu.
///
/// Annotate and Pin use the sink router's `annotate` / `pin` when those are set; otherwise
/// these notifications are posted for the editor (#25) and pin (#26) features to observe.
extension Notification.Name {
    /// Open a capture in the editor. userInfo: `QuickAccessUserInfo.result` (CaptureResult),
    /// optional `fileURL` (URL, once saved).
    static let openAnnotateRequested = Notification.Name("ScreenCapOpenAnnotateRequested")
    /// Pin a capture. userInfo as for `openAnnotateRequested`.
    static let pinRequested = Notification.Name("ScreenCapPinRequested")
    /// Re-show the most recently closed Quick Access capture. No userInfo.
    static let restoreRecentlyClosedRequested = Notification.Name("ScreenCapRestoreRecentlyClosedRequested")
}

/// userInfo keys used on the notifications above and on `.captureTextRequested` from Quick Access,
/// which carries `image` (CGImage) and `result` instead of a screen `rect`.
enum QuickAccessUserInfo {
    static let result = "result"
    static let fileURL = "fileURL"
    static let image = "image"
}

/// Quick Access preferences that aren't part of `AppSettings.quickAccess`.
enum QuickAccessPreferences {
    static let showAfterCaptureKey = "quickAccessShowAfterCapture"

    /// When off, the "Show Quick Access" after-capture action saves instead. Defaults to on.
    static var showAfterCapture: Bool {
        UserDefaults.standard.object(forKey: showAfterCaptureKey) as? Bool ?? true
    }
}

/// Whether overlays are temporarily hidden; read by the menu's checkmark.
@MainActor
enum QuickAccessVisibility {
    static var isHidden = false
}

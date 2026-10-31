import Foundation

/// Cross-feature requests (URL scheme, History, Quick Access, pins, editor).
/// Posted on `NotificationCenter.default`; see docs/url-scheme.md for each payload.
extension Notification.Name {
    /// Open an image in the editor. userInfo: `url` (file URL) or `result` (CaptureResult);
    /// neither means "ask for a file".
    static let openAnnotateRequested = Notification.Name("ScreenCapOpenAnnotateRequested")
    /// Pin an image. userInfo: `url` (file URL) or `result` (CaptureResult); neither means "ask for a file".
    static let pinRequested = Notification.Name("ScreenCapPinRequested")
    /// Show an image in Quick Access. userInfo: `url` (file URL), optional `recordID` (UUID).
    static let addQuickAccessOverlayRequested = Notification.Name("ScreenCapAddQuickAccessOverlayRequested")
    /// Bring back the most recently closed Quick Access overlay. No userInfo.
    static let restoreRecentlyClosedRequested = Notification.Name("ScreenCapRestoreRecentlyClosedRequested")
}

/// userInfo keys used by the automation notifications.
enum AutomationKey {
    static let url = "url"
    static let rect = "rect"
    static let lineBreaks = "lineBreaks"
    static let start = "start"
    static let autoscroll = "autoscroll"
    static let recordID = "recordID"
}

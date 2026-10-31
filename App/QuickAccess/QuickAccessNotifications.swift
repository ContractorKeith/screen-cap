import Foundation

// Shared notification names (openAnnotateRequested, pinRequested, restoreRecentlyClosedRequested)
// live in App/Automation/AutomationNotifications.swift.

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

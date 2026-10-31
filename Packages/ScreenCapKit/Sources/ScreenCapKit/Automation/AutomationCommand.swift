// Automation: typed model of every screencap:// command (PLAN §6, M7).
// Parsed by URLSchemeParser, rendered back by URLSchemeBuilder. See docs/url-scheme.md.

import Foundation

/// One command the app can run from a `screencap://` URL.
/// Optional values mean "not given in the URL": the app falls back to its own default
/// (interactive selection, the user's after-capture setting, and so on).
public enum AutomationCommand: Equatable, Sendable {
    case allInOne(region: Region?)
    case captureArea(region: Region?, action: AfterCaptureAction?)
    case capturePreviousArea(action: AfterCaptureAction?)
    case captureFullscreen(action: AfterCaptureAction?)
    case captureWindow(action: AfterCaptureAction?)
    case selfTimer(action: AfterCaptureAction?)
    case scrollingCapture(region: Region?, start: Bool, autoscroll: Bool)
    case captureText(source: TextSource?, lineBreaks: Bool)
    case openAnnotate(file: URL?)
    case pin(file: URL?)
    case openFromClipboard
    case openHistory
    case restoreRecentlyClosed
    case addQuickAccessOverlay(file: URL)
    case toggleDesktopIcons
    case hideDesktopIcons
    case showDesktopIcons
    case openSettings(tab: SettingsTab?)

    /// Where `capture-text` reads text from. `nil` source means "let the user select an area".
    public enum TextSource: Equatable, Sendable {
        case file(URL)
        case region(Region)
    }

    /// Settings tabs addressable from `open-settings`. Raw values are the URL spelling.
    public enum SettingsTab: String, CaseIterable, Sendable {
        case general, shortcuts, screenshots, annotate, wallpaper, history, advanced, about
        case quickAccess = "quickaccess"
    }

    /// The host name used in the URL, e.g. `capture-area`.
    public var name: String {
        switch self {
        case .allInOne: "all-in-one"
        case .captureArea: "capture-area"
        case .capturePreviousArea: "capture-previous-area"
        case .captureFullscreen: "capture-fullscreen"
        case .captureWindow: "capture-window"
        case .selfTimer: "self-timer"
        case .scrollingCapture: "scrolling-capture"
        case .captureText: "capture-text"
        case .openAnnotate: "open-annotate"
        case .pin: "pin"
        case .openFromClipboard: "open-from-clipboard"
        case .openHistory: "open-history"
        case .restoreRecentlyClosed: "restore-recently-closed"
        case .addQuickAccessOverlay: "add-quick-access-overlay"
        case .toggleDesktopIcons: "toggle-desktop-icons"
        case .hideDesktopIcons: "hide-desktop-icons"
        case .showDesktopIcons: "show-desktop-icons"
        case .openSettings: "open-settings"
        }
    }
}

/// A rectangle on one display, in points, with (0,0) at the display's lower-left corner.
public struct Region: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    /// 1-based display index.
    public var display: Int

    public init(x: Double, y: Double, width: Double, height: Double, display: Int = 1) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.display = display
    }
}

// `AfterCaptureAction` is defined in Settings/SettingsTypes.swift; raw values are the URL spelling.

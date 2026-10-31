import Foundation
import ScreenCapKit

/// Every UserDefaults key the app stores outside `AppSettings`, in one place so Reset All
/// Settings can't miss one. A new app-side preference adds its key here (the reset test fails
/// otherwise). Not settings, so not listed: keyboard shortcuts (KeyboardShortcuts), Sparkle's
/// update-check keys, and the welcome window's "don't show again".
enum SettingsKeys {
    /// Last-used Settings tab.
    static let settingsTab = "settingsTab"

    /// Plain-UserDefaults preferences shown in the panes.
    static let plain: [String] = [
        settingsTab,
        QuickAccessPreferences.showAfterCaptureKey,
        TextRecognitionPreferences.copyBarcodePayloadKey,
        // One-time "saving makes redactions permanent" confirmation; Reset asks again (#80).
        "EditorRedactionBakeConfirmed" // EditorDocumentModel.redactionBakeConfirmedKey (main-actor)
    ]

    /// `ScrollingSettings` (Scrolling pane).
    static let scrolling: [String] = [
        "scrolling.autoScroll", "scrolling.scrollStep", "scrolling.frameRate",
        "scrolling.maxLength", "scrolling.horizontal"
    ]

    /// `EditorPreferences` (Annotate pane and editor).
    static let editor: [String] = [
        "editor.defaultTool", "editor.rememberLastTool", "editor.lastTool", "editor.strokeColor",
        "editor.fillColor", "editor.strokeWidth", "editor.backgroundPresets"
    ]

    /// Every app-side key.
    static let all = plain + scrolling + editor
}

/// Reset All Settings (Advanced pane): `AppSettings` plus every key in `SettingsKeys`.
@MainActor
enum SettingsReset {
    static func resetAll(
        settings: AppSettings,
        scrolling: ScrollingSettings = .shared,
        editor: EditorPreferences = .shared,
        defaults: UserDefaults = .standard
    ) {
        settings.resetToDefaults()
        // Live objects first (their setters write defaults back), then remove every key so the
        // stored state matches a fresh install.
        scrolling.autoScroll = ScrollingSettings.Defaults.autoScroll
        scrolling.scrollStep = ScrollingSettings.Defaults.scrollStep
        scrolling.frameRate = ScrollingSettings.Defaults.frameRate
        scrolling.maxLength = ScrollingSettings.Defaults.maxLength
        scrolling.horizontal = ScrollingSettings.Defaults.horizontal

        let fresh = EditorPreferences(store: InMemorySettingsStore())
        editor.defaultTool = fresh.defaultTool
        editor.rememberLastTool = fresh.rememberLastTool
        editor.lastTool = fresh.lastTool
        editor.strokeColor = fresh.strokeColor
        editor.fillColor = fresh.fillColor
        editor.strokeWidth = fresh.strokeWidth
        editor.backgroundPresets = fresh.backgroundPresets

        SettingsKeys.all.forEach(defaults.removeObject(forKey:))
    }
}

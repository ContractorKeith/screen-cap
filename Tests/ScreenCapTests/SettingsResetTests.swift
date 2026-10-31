import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

@Suite("Settings navigation and reset")
@MainActor
struct SettingsResetTests {
    /// A throwaway defaults domain, removed when the test ends.
    final class Defaults {
        let name = "screencap.tests.\(UUID().uuidString)"
        let store: UserDefaults
        init() { store = UserDefaults(suiteName: name)! } // swiftlint:disable:this force_unwrapping
        deinit { UserDefaults().removePersistentDomain(forName: name) }
    }

    // MARK: - Tabs (#52)

    @Test func everySettingsTabHasAURLSpelling() {
        #expect(AutomationCommand.SettingsTab.allCases.map(\.rawValue) == [
            "general", "shortcuts", "quickaccess", "screenshots", "scrolling", "text",
            "annotate", "wallpaper", "advanced", "about"
        ])
    }

    @Test func invalidPersistedTabFallsBackToGeneral() {
        let defaults = Defaults()
        defaults.store.set("history", forKey: SettingsNavigation.defaultsKey)
        #expect(SettingsNavigation(defaults: defaults.store).tab == .general)
        defaults.store.removeObject(forKey: SettingsNavigation.defaultsKey)
        #expect(SettingsNavigation(defaults: defaults.store).tab == .general)
    }

    @Test func selectedTabPersists() {
        let defaults = Defaults()
        SettingsNavigation(defaults: defaults.store).tab = .scrolling
        #expect(defaults.store.string(forKey: SettingsNavigation.defaultsKey) == "scrolling")
        #expect(SettingsNavigation(defaults: defaults.store).tab == .scrolling)
    }

    // MARK: - Reset All Settings (#57)

    @Test func resetReturnsEveryPaneToDefaults() {
        let defaults = Defaults()
        let settings = AppSettings(store: UserDefaultsSettingsStore(suiteName: defaults.name))
        let scrolling = ScrollingSettings(defaults: defaults.store)
        let editor = EditorPreferences(store: UserDefaultsSettingsStore(suiteName: defaults.name))
        let navigation = SettingsNavigation(defaults: defaults.store)

        // Change something on every pane.
        settings.filenameTemplate = "custom"
        settings.ocrKeepLineBreaks = false
        settings.historyRetentionDays = 7
        scrolling.autoScroll = true
        scrolling.scrollStep = 300
        scrolling.frameRate = 30
        scrolling.maxLength = 5_000
        scrolling.horizontal = true
        editor.defaultTool = .text
        editor.rememberLastTool = false
        editor.lastTool = .rectangle
        editor.strokeColor = .black
        editor.fillColor = .white
        editor.strokeWidth = 12
        let background = Document.Background(fill: .solid(color: .white))
        editor.backgroundPresets = [BackgroundPreset(name: "P", background: background, aspect: 1)]
        navigation.tab = .advanced
        defaults.store.set(false, forKey: QuickAccessPreferences.showAfterCaptureKey)
        defaults.store.set(false, forKey: TextRecognitionPreferences.copyBarcodePayloadKey)

        // Every app-side key written above is in the registry.
        let written = Set(defaults.store.persistentDomain(forName: defaults.name)?.keys.map { $0 } ?? [])
        let appKeys = written.subtracting(AppSettings.Key.allCases.map(\.rawValue))
        #expect(appKeys.subtracting(SettingsKeys.all).isEmpty, "Missing from SettingsKeys: \(appKeys)")

        SettingsReset.resetAll(settings: settings, scrolling: scrolling, editor: editor, defaults: defaults.store)

        // Live objects show defaults.
        #expect(settings.filenameTemplate == AppSettings.Defaults.filenameTemplate)
        #expect(settings.ocrKeepLineBreaks)
        #expect(settings.historyRetentionDays == AppSettings.Defaults.historyRetentionDays)
        expectDefaults(scrolling)
        expectDefaults(editor)
        // Nothing app-side is left stored, so a relaunch reads defaults too.
        let stored = defaults.store.persistentDomain(forName: defaults.name) ?? [:]
        #expect(SettingsKeys.all.allSatisfy { stored[$0] == nil })
        expectDefaults(ScrollingSettings(defaults: defaults.store))
        expectDefaults(EditorPreferences(store: UserDefaultsSettingsStore(suiteName: defaults.name)))
        #expect(SettingsNavigation(defaults: defaults.store).tab == .general)
    }

    private func expectDefaults(_ scrolling: ScrollingSettings) {
        #expect(scrolling.autoScroll == ScrollingSettings.Defaults.autoScroll)
        #expect(scrolling.scrollStep == ScrollingSettings.Defaults.scrollStep)
        #expect(scrolling.frameRate == ScrollingSettings.Defaults.frameRate)
        #expect(scrolling.maxLength == ScrollingSettings.Defaults.maxLength)
        #expect(scrolling.horizontal == ScrollingSettings.Defaults.horizontal)
    }

    private func expectDefaults(_ editor: EditorPreferences) {
        let fresh = EditorPreferences(store: InMemorySettingsStore())
        #expect(editor.defaultTool == fresh.defaultTool)
        #expect(editor.rememberLastTool == fresh.rememberLastTool)
        #expect(editor.lastTool == fresh.lastTool)
        #expect(editor.strokeColor == fresh.strokeColor)
        #expect(editor.fillColor == fresh.fillColor)
        #expect(editor.strokeWidth == fresh.strokeWidth)
        #expect(editor.backgroundPresets == fresh.backgroundPresets)
    }
}

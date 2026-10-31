import CoreGraphics
import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

@Suite("Settings navigation and reset")
@MainActor
struct SettingsResetTests {
    // MARK: - Tabs (#52)

    @Test func everySettingsTabHasAURLSpelling() {
        #expect(AutomationCommand.SettingsTab.allCases.map(\.rawValue) == [
            "general", "shortcuts", "quickaccess", "screenshots", "scrolling", "text",
            "annotate", "wallpaper", "advanced", "about"
        ])
    }

    @Test func invalidPersistedTabFallsBackToGeneral() {
        let defaults = TemporaryDefaults()
        defer { defaults.remove() }
        defaults.store.set("history", forKey: SettingsNavigation.defaultsKey)
        #expect(SettingsNavigation(defaults: defaults.store).tab == .general)
        defaults.store.removeObject(forKey: SettingsNavigation.defaultsKey)
        #expect(SettingsNavigation(defaults: defaults.store).tab == .general)
    }

    @Test func selectedTabPersists() {
        let defaults = TemporaryDefaults()
        defer { defaults.remove() }
        SettingsNavigation(defaults: defaults.store).tab = .scrolling
        #expect(defaults.store.string(forKey: SettingsNavigation.defaultsKey) == "scrolling")
        #expect(SettingsNavigation(defaults: defaults.store).tab == .scrolling)
    }

    // MARK: - Reset All Settings (#57)

    @Test func resetReturnsEveryPaneToDefaults() {
        let defaults = TemporaryDefaults()
        defer { defaults.remove() }
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
        #expect(settings.historyRetentionDays == 7) // kept: it governs stored captures (#125)
        expectDefaults(scrolling)
        expectDefaults(editor)
        // Nothing app-side is left stored, so a relaunch reads defaults too.
        let stored = defaults.store.persistentDomain(forName: defaults.name) ?? [:]
        #expect(SettingsKeys.all.allSatisfy { stored[$0] == nil })
        expectDefaults(ScrollingSettings(defaults: defaults.store))
        expectDefaults(EditorPreferences(store: UserDefaultsSettingsStore(suiteName: defaults.name)))
        #expect(SettingsNavigation(defaults: defaults.store).tab == .general)
    }

    // MARK: - Reset keeps captures (#125)

    @Test func resetKeepsCapturesOlderThanTheDefaultRetention() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenCapResetTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // A capture made 60 days ago, kept by a 90-day retention.
        let sixtyDaysAgo = Date().addingTimeInterval(-60 * 86_400)
        let old = try await HistoryStore(directory: directory, retentionDays: nil, now: { sixtyDaysAgo })
            .add(image: Self.image(), kind: .area)
        let store = try HistoryStore(directory: directory, retentionDays: 90)
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.historyRetentionDays = 90
        let retention = HistoryRetention(store: store, settings: settings)
        retention.start()
        defer { retention.stop() }

        let defaults = TemporaryDefaults()
        defer { defaults.remove() }
        SettingsReset.resetAll(settings: settings, scrolling: ScrollingSettings(defaults: defaults.store),
                               editor: EditorPreferences(store: InMemorySettingsStore()), defaults: defaults.store)
        // Let any change-triggered purge run, then the hourly one.
        try await Task.sleep(for: .milliseconds(100))
        retention.purge()
        await retention.settled()

        #expect(settings.historyRetentionDays == 90)
        #expect(await store.record(id: old.id) != nil)
        #expect(FileManager.default.fileExists(atPath: old.fileURL.path))
    }

    private static func image() -> CGImage {
        let context = CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return context.makeImage()!
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

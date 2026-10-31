import CoreGraphics
import Foundation
@testable import ScreenCapKit
import Testing

@Suite("Wallpaper and history settings")
@MainActor
struct WallpaperSettingsTests {
    @Test func defaults() {
        let settings = AppSettings(store: InMemorySettingsStore())
        #expect(settings.wallpaper == WallpaperOptions())
        #expect(settings.wallpaper.style == .gradient)
        #expect(settings.historyRetentionDays == 30)
    }

    @Test func roundTrips() {
        let store = InMemorySettingsStore()
        let options = WallpaperOptions(style: .image, imageURL: URL(fileURLWithPath: "/tmp/bg.png"), padding: 20)
        let written = AppSettings(store: store)
        written.wallpaper = options
        written.historyRetentionDays = 7
        let read = AppSettings(store: store)
        #expect(read.wallpaper == options)
        #expect(read.historyRetentionDays == 7)
    }

    @Test func resetRestoresDefaults() {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)
        settings.filenameTemplate = "x"
        settings.historyRetentionDays = 3
        settings.wallpaper.style = .solid
        settings.resetToDefaults()
        #expect(settings.filenameTemplate == AppSettings.Defaults.filenameTemplate)
        #expect(settings.historyRetentionDays == 30)
        #expect(AppSettings(store: store).wallpaper == WallpaperOptions())
    }

    @Test func specFallsBackToGradientWithoutImage() {
        let spec = WallpaperOptions(style: .desktop, padding: 500).backgroundSpec(image: nil)
        guard case .linearGradient(let stops, _) = spec.fill else {
            Issue.record("expected gradient")
            return
        }
        #expect(stops.count == 2)
        #expect(spec.padding == EffectsInsets(all: 200))
    }

    @Test func solidSpec() {
        let spec = WallpaperOptions(style: .solid, solidColor: .white, padding: 10).backgroundSpec(image: nil)
        guard case .solid(let color) = spec.fill else {
            Issue.record("expected solid")
            return
        }
        #expect(color == .white)
        #expect(spec.padding == EffectsInsets(all: 10))
    }
}

import CoreGraphics
import Foundation
@testable import ScreenCapKit
import Testing

@Suite("AppSettings")
@MainActor
struct AppSettingsTests {
    @Test func defaults() {
        let settings = AppSettings(store: InMemorySettingsStore())
        #expect(settings.saveFolder == URL.desktopDirectory)
        #expect(settings.saveFolder.lastPathComponent == "Desktop")
        #expect(settings.filenameTemplate == "ScreenCap {date} at {time}")
        #expect(settings.imageFormat == .png)
        #expect(settings.retinaScale == .retina)
        #expect(settings.jpegQuality == 0.9)
        #expect(settings.copyMode == .image)
        #expect(settings.afterCaptureActions.isEmpty)
        for shortcut in CaptureShortcut.allCases {
            #expect(settings.afterCaptureAction(for: shortcut) == .overlay)
        }
        #expect(settings.freezeScreen)
        #expect(settings.showCrosshair)
        #expect(settings.showMagnifier)
        #expect(settings.quickAccess == QuickAccessOptions(
            position: .bottomLeft, size: .medium, autoCloseSeconds: nil, display: .withCursor
        ))
        #expect(!settings.hideDesktopIcons)
        #expect(!settings.launchAtLogin)
        #expect(settings.lastCaptureRect == nil)
        #expect(settings.colorPalette == AppSettings.Defaults.colorPalette)
        #expect(!settings.colorPalette.isEmpty)
        #expect(settings.ocrKeepLineBreaks)
        #expect(settings.ocrLanguages == ["en-US"])
    }

    @Test func defaultsWriteNothing() {
        let store = InMemorySettingsStore()
        _ = AppSettings(store: store)
        #expect(store.values.isEmpty)
    }

    @Test func roundTripsEverySetting() {
        let store = InMemorySettingsStore()
        let palette = [RGBAColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)]
        let quickAccess = QuickAccessOptions(
            position: .topRight, size: .large, autoCloseSeconds: 5, display: .main
        )
        let rect = CGRect(x: -1440, y: 120.5, width: 800, height: 600)
        let folder = URL(fileURLWithPath: "/tmp/Shots with space", isDirectory: true)

        let written = AppSettings(store: store)
        written.saveFolder = folder
        written.filenameTemplate = "{app} {counter}"
        written.imageFormat = .heic
        written.retinaScale = .standard
        written.jpegQuality = 0.5
        written.copyMode = .file
        written.setAfterCaptureAction(.pin, for: .area)
        written.setAfterCaptureAction(.save, for: .scrolling)
        written.freezeScreen = false
        written.showCrosshair = false
        written.showMagnifier = false
        written.quickAccess = quickAccess
        written.hideDesktopIcons = true
        written.launchAtLogin = true
        written.lastCaptureRect = rect
        written.colorPalette = palette
        written.ocrKeepLineBreaks = false
        written.ocrLanguages = ["de-DE", "en-US"]

        let read = AppSettings(store: store)
        #expect(read.saveFolder == folder)
        #expect(read.filenameTemplate == "{app} {counter}")
        #expect(read.imageFormat == .heic)
        #expect(read.retinaScale == .standard)
        #expect(read.jpegQuality == 0.5)
        #expect(read.copyMode == .file)
        #expect(read.afterCaptureAction(for: .area) == .pin)
        #expect(read.afterCaptureAction(for: .scrolling) == .save)
        #expect(read.afterCaptureAction(for: .window) == .overlay)
        #expect(!read.freezeScreen)
        #expect(!read.showCrosshair)
        #expect(!read.showMagnifier)
        #expect(read.quickAccess == quickAccess)
        #expect(read.hideDesktopIcons)
        #expect(read.launchAtLogin)
        #expect(read.lastCaptureRect == rect)
        #expect(read.colorPalette == palette)
        #expect(!read.ocrKeepLineBreaks)
        #expect(read.ocrLanguages == ["de-DE", "en-US"])
    }

    @Test func clearingLastCaptureRectPersists() {
        let store = InMemorySettingsStore()
        let written = AppSettings(store: store)
        written.lastCaptureRect = CGRect(x: 0, y: 0, width: 10, height: 10)
        written.lastCaptureRect = nil
        #expect(AppSettings(store: store).lastCaptureRect == nil)
    }

    @Test func corruptValueFallsBackToDefault() {
        let store = InMemorySettingsStore(values: [
            AppSettings.Key.imageFormat.rawValue: Data("\"bmp\"".utf8),
            AppSettings.Key.jpegQuality.rawValue: Data("garbage".utf8)
        ])
        let settings = AppSettings(store: store)
        #expect(settings.imageFormat == .png)
        #expect(settings.jpegQuality == 0.9)
    }

    @Test func userDefaultsStoreRoundTrips() throws {
        let suite = "com.contractorkeith.screencap.tests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let written = AppSettings(store: UserDefaultsSettingsStore(suiteName: suite))
        written.imageFormat = .tiff
        written.jpegQuality = 0.25
        let read = AppSettings(store: UserDefaultsSettingsStore(suiteName: suite))
        #expect(read.imageFormat == .tiff)
        #expect(read.jpegQuality == 0.25)
    }

    @Test func saveOptionsMirrorSettings() {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.imageFormat = .jpeg
        settings.retinaScale = .standard
        settings.jpegQuality = 0.7
        settings.filenameTemplate = "{kind} {date}"
        let folder = URL(fileURLWithPath: "/tmp/out", isDirectory: true)
        settings.saveFolder = folder

        #expect(settings.saveOptions == SaveOptions(
            format: .jpeg, scale: .standard, jpegQuality: 0.7, folder: folder, filenameTemplate: "{kind} {date}"
        ))
    }

    @Test(arguments: [(-0.5, 0.0), (0.0, 0.0), (0.42, 0.42), (1.0, 1.0), (3.0, 1.0)])
    func saveOptionsClampQuality(input: Double, expected: Double) {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.jpegQuality = input
        #expect(settings.saveOptions.jpegQuality == expected)
    }

    @Test func saveOptionsBuildTemplate() {
        let options = SaveOptions(
            format: .tiff, scale: .retina, jpegQuality: 1, folder: URL(fileURLWithPath: "/tmp"),
            filenameTemplate: "Shot {date}"
        )
        let template = options.template(clock: { Date(timeIntervalSince1970: 0) }, timeZone: .gmt)
        #expect(template.filename() == "Shot 1970-01-01.tiff")
    }

    @Test func formatExtensionsAndScale() {
        #expect(ImageFormat.allCases.map(\.fileExtension) == ["png", "jpg", "heic", "tiff"])
        #expect(RetinaScale.retina.factor == 2)
        #expect(RetinaScale.standard.factor == 1)
    }
}

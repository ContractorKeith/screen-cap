import CoreGraphics
import Foundation
import Observation

/// Typed app settings. Every property loads from the store at init and writes back on change.
@MainActor
@Observable
public final class AppSettings {
    /// Storage keys. Raw values are the persisted key names; don't rename them.
    public enum Key: String, CaseIterable, Sendable {
        case saveFolder, filenameTemplate, imageFormat, retinaScale, jpegQuality, copyMode
        case afterCaptureActions, freezeScreen, showCrosshair, showMagnifier, quickAccess
        case hideDesktopIcons, launchAtLogin, lastCaptureRect, colorPalette
        case ocrKeepLineBreaks, ocrLanguages
    }

    /// Default values, shared with tests.
    public enum Defaults {
        public static let saveFolder = URL.desktopDirectory
        public static let filenameTemplate = "ScreenCap {date} at {time}"
        public static let imageFormat = ImageFormat.png
        public static let retinaScale = RetinaScale.retina
        public static let jpegQuality = 0.9
        public static let copyMode = CopyMode.image
        public static let afterCaptureAction = AfterCaptureAction.overlay
        public static let quickAccess = QuickAccessOptions()
        public static let colorPalette: [RGBAColor] = [
            RGBAColor(red: 0.96, green: 0.26, blue: 0.21),
            RGBAColor(red: 1.00, green: 0.76, blue: 0.03),
            RGBAColor(red: 0.30, green: 0.69, blue: 0.31),
            RGBAColor(red: 0.13, green: 0.59, blue: 0.95),
            RGBAColor(red: 0.61, green: 0.15, blue: 0.69),
            RGBAColor(red: 0, green: 0, blue: 0),
            RGBAColor(red: 1, green: 1, blue: 1)
        ]
        public static let ocrLanguages = ["en-US"]
    }

    @ObservationIgnored private let store: any SettingsStore

    public var saveFolder: URL { didSet { persist(.saveFolder, saveFolder) } }
    public var filenameTemplate: String { didSet { persist(.filenameTemplate, filenameTemplate) } }
    public var imageFormat: ImageFormat { didSet { persist(.imageFormat, imageFormat) } }
    public var retinaScale: RetinaScale { didSet { persist(.retinaScale, retinaScale) } }
    /// 0.0...1.0. Out-of-range values are clamped when read through `saveOptions`.
    public var jpegQuality: Double { didSet { persist(.jpegQuality, jpegQuality) } }
    public var copyMode: CopyMode { didSet { persist(.copyMode, copyMode) } }
    /// Overrides per shortcut; missing entries fall back to `Defaults.afterCaptureAction`.
    public var afterCaptureActions: [CaptureShortcut: AfterCaptureAction] {
        didSet { persist(.afterCaptureActions, afterCaptureActions) }
    }
    public var freezeScreen: Bool { didSet { persist(.freezeScreen, freezeScreen) } }
    public var showCrosshair: Bool { didSet { persist(.showCrosshair, showCrosshair) } }
    public var showMagnifier: Bool { didSet { persist(.showMagnifier, showMagnifier) } }
    public var quickAccess: QuickAccessOptions { didSet { persist(.quickAccess, quickAccess) } }
    public var hideDesktopIcons: Bool { didSet { persist(.hideDesktopIcons, hideDesktopIcons) } }
    /// Mirror of `SMAppService.mainApp` status for the UI; the app shell owns the real toggle.
    public var launchAtLogin: Bool { didSet { persist(.launchAtLogin, launchAtLogin) } }
    /// Last area selection in global screen coordinates, for Previous Area.
    public var lastCaptureRect: CGRect? { didSet { persist(.lastCaptureRect, lastCaptureRect) } }
    public var colorPalette: [RGBAColor] { didSet { persist(.colorPalette, colorPalette) } }
    public var ocrKeepLineBreaks: Bool { didSet { persist(.ocrKeepLineBreaks, ocrKeepLineBreaks) } }
    /// BCP 47 language codes for Vision text recognition, in priority order.
    public var ocrLanguages: [String] { didSet { persist(.ocrLanguages, ocrLanguages) } }

    public init(store: any SettingsStore = UserDefaultsSettingsStore()) {
        self.store = store
        saveFolder = Self.load(.saveFolder, from: store) ?? Defaults.saveFolder
        filenameTemplate = Self.load(.filenameTemplate, from: store) ?? Defaults.filenameTemplate
        imageFormat = Self.load(.imageFormat, from: store) ?? Defaults.imageFormat
        retinaScale = Self.load(.retinaScale, from: store) ?? Defaults.retinaScale
        jpegQuality = Self.load(.jpegQuality, from: store) ?? Defaults.jpegQuality
        copyMode = Self.load(.copyMode, from: store) ?? Defaults.copyMode
        afterCaptureActions = Self.load(.afterCaptureActions, from: store) ?? [:]
        freezeScreen = Self.load(.freezeScreen, from: store) ?? true
        showCrosshair = Self.load(.showCrosshair, from: store) ?? true
        showMagnifier = Self.load(.showMagnifier, from: store) ?? true
        quickAccess = Self.load(.quickAccess, from: store) ?? Defaults.quickAccess
        hideDesktopIcons = Self.load(.hideDesktopIcons, from: store) ?? false
        launchAtLogin = Self.load(.launchAtLogin, from: store) ?? false
        lastCaptureRect = Self.load(.lastCaptureRect, from: store) ?? nil
        colorPalette = Self.load(.colorPalette, from: store) ?? Defaults.colorPalette
        ocrKeepLineBreaks = Self.load(.ocrKeepLineBreaks, from: store) ?? true
        ocrLanguages = Self.load(.ocrLanguages, from: store) ?? Defaults.ocrLanguages
    }

    /// After-capture action for a shortcut, falling back to the default.
    public func afterCaptureAction(for shortcut: CaptureShortcut) -> AfterCaptureAction {
        afterCaptureActions[shortcut] ?? Defaults.afterCaptureAction
    }

    public func setAfterCaptureAction(_ action: AfterCaptureAction, for shortcut: CaptureShortcut) {
        afterCaptureActions[shortcut] = action
    }

    /// Snapshot of the save-related settings for the exporter.
    public var saveOptions: SaveOptions {
        SaveOptions(
            format: imageFormat,
            scale: retinaScale,
            jpegQuality: jpegQuality,
            folder: saveFolder,
            filenameTemplate: filenameTemplate
        )
    }

    // MARK: - Persistence

    /// Decodes a stored value; nil when missing or unreadable (so the default applies).
    private static func load<Value: Decodable>(_ key: Key, from store: any SettingsStore) -> Value? {
        guard let data = store.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    private func persist<Value: Encodable>(_ key: Key, _ value: Value) {
        store.set(try? JSONEncoder().encode(value), forKey: key.rawValue)
    }
}

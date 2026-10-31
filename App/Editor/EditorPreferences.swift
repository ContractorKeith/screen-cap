import Foundation
import Observation
import ScreenCapKit

/// A saved Background tool setup, applied from the Background panel.
struct BackgroundPreset: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var background: Document.Background
    var aspect: Double?
}

/// Annotate settings (PLAN §3.4): default tool, colors, stroke width, remember last tool, and
/// Background presets. Stored as JSON under `editor.*` keys in the same store as `AppSettings`.
/// The color palette itself lives in `AppSettings.colorPalette`.
@MainActor
@Observable
final class EditorPreferences {
    static let shared = EditorPreferences()

    @ObservationIgnored private let store: any SettingsStore

    var defaultTool: EditorTool { didSet { persist("defaultTool", defaultTool) } }
    var rememberLastTool: Bool { didSet { persist("rememberLastTool", rememberLastTool) } }
    var lastTool: EditorTool { didSet { persist("lastTool", lastTool) } }
    var strokeColor: RGBAColor { didSet { persist("strokeColor", strokeColor) } }
    /// Fill for new shapes; nil means no fill.
    var fillColor: RGBAColor? { didSet { persist("fillColor", fillColor) } }
    var strokeWidth: Double { didSet { persist("strokeWidth", strokeWidth) } }
    var backgroundPresets: [BackgroundPreset] { didSet { persist("backgroundPresets", backgroundPresets) } }

    init(store: any SettingsStore = UserDefaultsSettingsStore()) {
        self.store = store
        defaultTool = Self.load("defaultTool", store) ?? .arrow
        rememberLastTool = Self.load("rememberLastTool", store) ?? true
        lastTool = Self.load("lastTool", store) ?? .arrow
        strokeColor = Self.load("strokeColor", store) ?? .red
        fillColor = Self.load("fillColor", store) ?? nil
        strokeWidth = Self.load("strokeWidth", store) ?? 4
        backgroundPresets = Self.load("backgroundPresets", store) ?? []
    }

    /// Tool a new editor window starts with.
    var initialTool: EditorTool {
        let tool = rememberLastTool ? lastTool : defaultTool
        return tool == .crop ? .select : tool
    }

    /// Tool options for a new editor window.
    var toolOptions: ToolOptions {
        var options = ToolOptions()
        options.style = Annotation.Style(strokeColor: strokeColor, strokeWidth: strokeWidth, fillColor: fillColor)
        return options
    }

    private static func load<Value: Decodable>(_ key: String, _ store: any SettingsStore) -> Value? {
        guard let data = store.data(forKey: "editor.\(key)") else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    private func persist<Value: Encodable>(_ key: String, _ value: Value) {
        store.set(try? JSONEncoder().encode(value), forKey: "editor.\(key)")
    }
}

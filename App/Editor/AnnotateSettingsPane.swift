import AppKit
import ScreenCapKit
import SwiftUI

/// Settings ▸ Annotate: default tool, default colors and stroke width, remember last tool, palette.
struct AnnotateSettingsPane: View {
    @Bindable var settings: AppSettings
    @Bindable var preferences: EditorPreferences = .shared

    var body: some View {
        Form {
            Section("Tools") {
                Picker("Default tool", selection: $preferences.defaultTool) {
                    ForEach(EditorTool.allCases.filter { $0 != .crop }) { Text($0.title).tag($0) }
                }
                .disabled(preferences.rememberLastTool)
                Toggle("Remember last used tool", isOn: $preferences.rememberLastTool)
            }
            Section("Defaults for new objects") {
                ColorPicker("Stroke color", selection: colorBinding(\.strokeColor))
                Toggle("Fill shapes", isOn: Binding { preferences.fillColor != nil } set: { isOn in
                    preferences.fillColor = isOn ? (preferences.fillColor ?? .white) : nil
                })
                if preferences.fillColor != nil {
                    ColorPicker("Fill color", selection: Binding {
                        Color(nsColor: (preferences.fillColor ?? .white).nsColor)
                    } set: { preferences.fillColor = RGBAColor(NSColor($0)) })
                }
                LabeledContent("Stroke width") {
                    HStack {
                        Slider(value: $preferences.strokeWidth, in: 1...40)
                        Text("\(Int(preferences.strokeWidth)) px").monospacedDigit().frame(width: 44)
                    }
                }
            }
            Section("Color palette") {
                ColorSection(title: nil, color: preferences.strokeColor, palette: $settings.colorPalette) { color in
                    preferences.strokeColor = color
                }
                Button("Reset Palette") { settings.colorPalette = AppSettings.Defaults.colorPalette }
            }
        }
        .formStyle(.grouped)
    }

    private func colorBinding(_ keyPath: ReferenceWritableKeyPath<EditorPreferences, RGBAColor>) -> Binding<Color> {
        Binding { Color(nsColor: preferences[keyPath: keyPath].nsColor) } set: {
            preferences[keyPath: keyPath] = RGBAColor(NSColor($0))
        }
    }
}

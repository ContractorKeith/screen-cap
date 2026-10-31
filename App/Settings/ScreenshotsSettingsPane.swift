import ScreenCapKit
import SwiftUI

/// File naming, format and capture behaviour.
struct ScreenshotsSettingsPane: View {
    @Bindable var settings: AppSettings

    /// Filename tokens with a one-line explanation each (FilenameTemplate).
    static let tokens: [(token: String, meaning: String)] = [
        ("{date}", "2026-10-31"),
        ("{time}", "14.05.09"),
        ("{datetime}", "date and time"),
        ("{app}", "frontmost app"),
        ("{window}", "window title"),
        ("{kind}", "area, window, fullscreen…"),
        ("{counter}", "1, 2, 3… avoids collisions")
    ]

    var body: some View {
        Form {
            Section("File name") {
                TextField("Template", text: $settings.filenameTemplate)
                LabeledContent("Preview") {
                    Text(preview).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                    ForEach(Self.tokens, id: \.token) { entry in
                        GridRow {
                            Text(entry.token).font(.caption.monospaced())
                            Text(entry.meaning).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Format") {
                Picker("Format", selection: $settings.imageFormat) {
                    ForEach(ImageFormat.allCases, id: \.self) { Text($0.fileExtension.uppercased()).tag($0) }
                }
                if settings.imageFormat == .jpeg || settings.imageFormat == .heic {
                    LabeledContent("Quality") {
                        HStack {
                            Slider(value: $settings.jpegQuality, in: 0.1...1)
                            Text(settings.jpegQuality, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                Picker("Scale", selection: $settings.retinaScale) {
                    Text("Retina (2x)").tag(RetinaScale.retina)
                    Text("Standard (1x)").tag(RetinaScale.standard)
                }
                Picker("Copy as", selection: $settings.copyMode) {
                    Text("Image").tag(CopyMode.image)
                    Text("File").tag(CopyMode.file)
                }
            }
            Section("Capture") {
                Toggle("Freeze screen while selecting", isOn: $settings.freezeScreen)
                Toggle("Show crosshair", isOn: $settings.showCrosshair)
                Toggle("Show magnifier", isOn: $settings.showMagnifier)
                Toggle("Window shadow", isOn: $settings.windowShadow)
                Toggle("Fullscreen captures every display", isOn: $settings.fullscreenAllDisplays)
                Toggle("Hide desktop icons while capturing", isOn: $settings.hideDesktopIcons)
                Picker("Self-timer", selection: $settings.selfTimerSeconds) {
                    ForEach(AppSettings.Defaults.selfTimerChoices, id: \.self) { Text("\($0) seconds").tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var preview: String {
        settings.saveOptions.template()
            .filename(context: FilenameTemplate.Context(app: "Safari", window: "Start Page", kind: .area))
    }
}

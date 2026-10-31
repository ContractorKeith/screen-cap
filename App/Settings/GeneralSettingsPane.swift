import AppKit
import ScreenCapKit
import SwiftUI

/// Save, copy and capture options bound to `AppSettings`.
struct GeneralSettingsPane: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Saving") {
                LabeledContent("Save to") {
                    HStack {
                        Text(settings.saveFolder.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                TextField("File name", text: $settings.filenameTemplate)
                Text("Tokens: {date} {time} {datetime} {app} {window} {kind} {counter}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Format", selection: $settings.imageFormat) {
                    ForEach(ImageFormat.allCases, id: \.self) { Text($0.fileExtension.uppercased()).tag($0) }
                }
                if settings.imageFormat == .jpeg || settings.imageFormat == .heic {
                    Slider(value: $settings.jpegQuality, in: 0.1...1) { Text("Quality") }
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
                Picker("Self-timer", selection: $settings.selfTimerSeconds) {
                    ForEach(AppSettings.Defaults.selfTimerChoices, id: \.self) { Text("\($0) seconds").tag($0) }
                }
            }
            Section("After capture") {
                ForEach(CaptureShortcut.allCases, id: \.self) { shortcut in
                    Picker(Self.title(for: shortcut), selection: actionBinding(for: shortcut)) {
                        ForEach(AfterCaptureAction.allCases, id: \.self) { Text(Self.title(for: $0)).tag($0) }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func actionBinding(for shortcut: CaptureShortcut) -> Binding<AfterCaptureAction> {
        Binding(
            get: { settings.afterCaptureAction(for: shortcut) },
            set: { settings.setAfterCaptureAction($0, for: shortcut) }
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.saveFolder
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveFolder = url
        }
    }

    static func title(for shortcut: CaptureShortcut) -> String {
        switch shortcut {
        case .area: "Area"
        case .previousArea: "Previous area"
        case .window: "Window"
        case .fullscreen: "Fullscreen"
        case .scrolling: "Scrolling"
        case .selfTimer: "Self-timer"
        }
    }

    static func title(for action: AfterCaptureAction) -> String {
        switch action {
        case .overlay: "Show Quick Access"
        case .copy: "Copy"
        case .save: "Save"
        case .annotate: "Annotate"
        case .pin: "Pin"
        }
    }
}

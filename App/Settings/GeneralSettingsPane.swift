import AppKit
import ScreenCapKit
import SwiftUI

/// Save folder and after-capture actions. File and capture options live in Screenshots.
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
                Text("File name, format and capture options are under Screenshots.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

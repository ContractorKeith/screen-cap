import ScreenCapKit
import SwiftUI

/// Capture Text options: line breaks, recognition languages, QR payload copying.
struct TextRecognitionSettingsPane: View {
    @Bindable var settings: AppSettings
    @AppStorage(TextRecognitionPreferences.copyBarcodePayloadKey) private var copyBarcodePayload = true
    @State private var available: [String] = []

    var body: some View {
        Form {
            Section("Text") {
                Toggle("Keep line breaks", isOn: $settings.ocrKeepLineBreaks)
                Toggle("Copy QR and barcode payload instead of text", isOn: $copyBarcodePayload)
            }
            Section {
                List(available, id: \.self) { code in
                    Toggle(Self.displayName(code), isOn: binding(for: code))
                }
                .frame(minHeight: 260)
            } header: {
                Text("Languages")
            } footer: {
                Text("Checked languages are tried in the order you picked them. None checked: detect automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            available = (try? await TextRecognizer().supportedLanguages()) ?? settings.ocrLanguages
        }
    }

    /// Adds a language at the end (lowest priority) or removes it.
    private func binding(for code: String) -> Binding<Bool> {
        Binding(
            get: { settings.ocrLanguages.contains(code) },
            set: { isOn in
                settings.ocrLanguages.removeAll { $0 == code }
                if isOn { settings.ocrLanguages.append(code) }
            }
        )
    }

    /// "English (United States)" for "en-US".
    static func displayName(_ code: String) -> String {
        let name = Locale.current.localizedString(forIdentifier: code) ?? code
        return "\(name) — \(code)"
    }
}

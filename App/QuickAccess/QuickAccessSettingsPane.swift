import ScreenCapKit
import SwiftUI

/// Quick Access options bound to `AppSettings.quickAccess`.
struct QuickAccessSettingsPane: View {
    @Bindable var settings: AppSettings
    @AppStorage(QuickAccessPreferences.showAfterCaptureKey) private var showAfterCapture = true

    static let autoCloseChoices = [5, 10, 15, 30, 60]

    var body: some View {
        Form {
            Section {
                Toggle("Show Quick Access after capture", isOn: $showAfterCapture)
                Text("When off, captures set to Show Quick Access are saved instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Overlay") {
                Picker("Position", selection: $settings.quickAccess.position) {
                    ForEach(ScreenCorner.allCases, id: \.self) { Text(Self.title(for: $0)).tag($0) }
                }
                Picker("Size", selection: $settings.quickAccess.size) {
                    ForEach(QuickAccessSize.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("Display", selection: $settings.quickAccess.display) {
                    Text("Display with the pointer").tag(QuickAccessDisplay.withCursor)
                    Text("Main display").tag(QuickAccessDisplay.main)
                }
                Picker("Close automatically", selection: $settings.quickAccess.autoCloseSeconds) {
                    Text("Never").tag(Int?.none)
                    ForEach(Self.autoCloseChoices, id: \.self) { Text("After \($0) seconds").tag(Int?.some($0)) }
                }
            }
        }
        .formStyle(.grouped)
    }

    static func title(for corner: ScreenCorner) -> String {
        switch corner {
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        case .topLeft: "Top left"
        case .topRight: "Top right"
        }
    }
}

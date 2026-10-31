@preconcurrency import KeyboardShortcuts
import SwiftUI

/// One recorder per global shortcut.
struct ShortcutsSettingsPane: View {
    var body: some View {
        Form {
            Section {
                ForEach(ShortcutCatalog.all, id: \.name) { entry in
                    LabeledContent(entry.title) {
                        KeyboardShortcuts.Recorder(for: entry.name)
                    }
                }
            } footer: {
                Text("Defaults use ⌃⇧ so they don't replace the macOS ⇧⌘3/4/5 shortcuts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Restore Defaults") {
                KeyboardShortcuts.reset(ShortcutCatalog.all.map(\.name))
            }
        }
        .formStyle(.grouped)
    }
}

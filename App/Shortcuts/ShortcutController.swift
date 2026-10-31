@preconcurrency import KeyboardShortcuts

/// Wires every catalog shortcut to its command. Handlers fire on key up, on the main thread.
@MainActor
final class ShortcutController {
    private let perform: @MainActor (ShortcutCatalog.Command) -> Void

    init(perform: @escaping @MainActor (ShortcutCatalog.Command) -> Void) {
        self.perform = perform
    }

    func register() {
        for entry in ShortcutCatalog.all {
            let command = entry.command
            KeyboardShortcuts.onKeyUp(for: entry.name) { [weak self] in
                MainActor.assumeIsolated { self?.perform(command) }
            }
        }
    }
}

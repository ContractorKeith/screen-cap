import Foundation

/// One save per capture (#78). Concurrent saves of the same key (double-click on Save, Save plus the
/// save swipe, Reveal during a save) share the first one's result instead of writing `X 2.png`.
/// Keyed by history record ID when there is one, so two panels of one record also share it.
@MainActor
final class QuickAccessSaveGate<Key: Hashable> {
    private var inFlight: [Key: Task<URL?, Never>] = [:]

    func isSaving(_ key: Key) -> Bool { inFlight[key] != nil }

    /// Runs `save` unless a save for `key` is already running; either way returns that save's URL.
    func save(_ key: Key, _ save: @escaping @MainActor () async -> URL?) async -> URL? {
        if let running = inFlight[key] { return await running.value }
        let task = Task { await save() }
        inFlight[key] = task
        let url = await task.value
        inFlight[key] = nil
        return url
    }

    /// The running save's result, or nil at once when none is running.
    func pending(_ key: Key) async -> URL? {
        await inFlight[key]?.value
    }
}

/// What a Quick Access panel saves under: its history record, else the panel itself.
enum QuickAccessSaveKey: Hashable {
    case record(UUID)
    case panel(ObjectIdentifier)
}

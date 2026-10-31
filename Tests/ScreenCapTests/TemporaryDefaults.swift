import Foundation

/// A throwaway `UserDefaults` suite for tests (#120); call `remove()` in a `defer`.
/// The suite name is an absolute path in a temporary folder, so cfprefsd writes `<folder>/suite.plist`
/// instead of `~/Library/Preferences/<name>.plist` (which it rewrites even after
/// `removePersistentDomain` and a file delete). `remove()` clears the domain and deletes the folder.
final class TemporaryDefaults: @unchecked Sendable {
    let folder: URL
    /// Pass to `UserDefaults(suiteName:)` or `UserDefaultsSettingsStore(suiteName:)` for the same domain.
    let name: String
    let store: UserDefaults

    init() {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("screencap-tests-defaults-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        name = folder.appendingPathComponent("suite").path
        store = UserDefaults(suiteName: name)! // swiftlint:disable:this force_unwrapping
    }

    func remove() {
        store.removePersistentDomain(forName: name)
        try? FileManager.default.removeItem(at: folder)
    }
}

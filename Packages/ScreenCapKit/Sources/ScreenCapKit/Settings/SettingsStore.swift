import Foundation

/// Raw key-value storage behind `AppSettings`. Values are JSON-encoded `Data` so one
/// small protocol covers every setting type.
public protocol SettingsStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

/// Production store: a UserDefaults suite (standard defaults when `suiteName` is nil).
public final class UserDefaultsSettingsStore: SettingsStore {
    private let defaults: UserDefaults

    public init(suiteName: String? = ScreenCapKit.bundleIdentifier) {
        defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    public func set(_ data: Data?, forKey key: String) {
        defaults.set(data, forKey: key)
    }
}

/// Test store: a plain dictionary.
public final class InMemorySettingsStore: SettingsStore {
    public private(set) var values: [String: Data]

    public init(values: [String: Data] = [:]) {
        self.values = values
    }

    public func data(forKey key: String) -> Data? {
        values[key]
    }

    public func set(_ data: Data?, forKey key: String) {
        values[key] = data
    }
}

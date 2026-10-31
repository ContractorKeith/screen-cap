import Foundation
import ScreenCapKit
import Testing

/// #120: test suites must not leave plists in ~/Library/Preferences.
@Suite("Temporary defaults")
struct TemporaryDefaultsTests {
    @Test func writesOutsidePreferencesAndCleansUp() {
        let suite = TemporaryDefaults()
        suite.store.set(true, forKey: "flag")
        UserDefaultsSettingsStore(suiteName: suite.name).set(Data([1]), forKey: "data")
        #expect(UserDefaults(suiteName: suite.name)?.bool(forKey: "flag") == true)
        #expect(UserDefaultsSettingsStore(suiteName: suite.name).data(forKey: "data") == Data([1]))
        #expect(suite.name.hasPrefix(FileManager.default.temporaryDirectory.path))

        suite.remove()
        #expect(!FileManager.default.fileExists(atPath: suite.folder.path))
        #expect(UserDefaults(suiteName: suite.name)?.object(forKey: "flag") == nil)
    }
}

import Foundation
import ScreenCapKit
import Testing

/// #120: test suites must not leave plists in ~/Library/Preferences. Checks where cfprefsd actually
/// writes, through a full write → flush → remove lifecycle (#135).
@Suite("Temporary defaults")
struct TemporaryDefaultsTests {
    @Test func writesOutsidePreferencesAndCleansUp() throws {
        let suite = TemporaryDefaults()
        let marker = suite.folder.lastPathComponent // contains the suite's UUID
        suite.store.set(true, forKey: "flag")
        let settings = UserDefaultsSettingsStore(suiteName: suite.name)
        settings.set(Data([1]), forKey: "data")
        #expect(UserDefaults(suiteName: suite.name)?.bool(forKey: "flag") == true)
        #expect(settings.data(forKey: "data") == Data([1]))
        // Flush to disk; the plist must land in the temp folder, nowhere in ~/Library/Preferences.
        _ = suite.store.synchronize()
        _ = UserDefaults(suiteName: suite.name)?.synchronize()
        #expect(FileManager.default.fileExists(atPath: suite.name + ".plist"))
        #expect(try Self.preferencesPlists(containing: marker).isEmpty)

        suite.remove()
        #expect(!FileManager.default.fileExists(atPath: suite.folder.path))
        #expect(UserDefaults(suiteName: suite.name)?.object(forKey: "flag") == nil)
        // cfprefsd rewrote named suites after removal (#120); give it a moment, then check again.
        _ = UserDefaults(suiteName: suite.name)?.synchronize()
        Thread.sleep(forTimeInterval: 0.3)
        #expect(try Self.preferencesPlists(containing: marker).isEmpty)
        try? FileManager.default.removeItem(at: suite.folder) // the reads above may recreate it
    }

    private static func preferencesPlists(containing marker: String) throws -> [String] {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences")
        let uuid = String(marker.suffix(36))
        return try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.contains(uuid) }
    }
}

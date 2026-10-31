import Foundation
@testable import ScreenCapKit
import Testing

@Suite("ScreenCapKit constants")
struct ScreenCapKitConstantsTests {
    @Test func versionIsSemVer() {
        let parts = ScreenCapKit.version.split(separator: ".")
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { Int($0) != nil })
    }

    @Test func identifiersMatchInfoPlist() throws {
        // Resolve App/Resources/Info.plist relative to this file so the test runs from any cwd.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let plistURL = root.appendingPathComponent("App/Resources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        #expect(plist["CFBundleIdentifier"] as? String == ScreenCapKit.bundleIdentifier)
        #expect(plist["CFBundleShortVersionString"] as? String == ScreenCapKit.version)
        let urlTypes = try #require(plist["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.contains(ScreenCapKit.urlScheme))
    }
}

import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

@Suite("Updater configuration")
struct UpdaterConfigurationTests {
    private let feed = "https://github.com/ContractorKeith/screen-cap/releases/latest/download/appcast.xml"

    @Test func placeholderKeyKeepsUpdaterOff() {
        let config = UpdaterConfiguration(info: [
            "SUFeedURL": feed, "SUPublicEDKey": UpdaterConfiguration.placeholderKey
        ])
        #expect(!config.isEnabled)
    }

    @Test func missingOrEmptyKeyKeepsUpdaterOff() {
        #expect(!UpdaterConfiguration(info: ["SUFeedURL": feed]).isEnabled)
        #expect(!UpdaterConfiguration(info: ["SUFeedURL": feed, "SUPublicEDKey": "  "]).isEnabled)
        #expect(!UpdaterConfiguration(info: ["SUPublicEDKey": "abc123="]).isEnabled)
    }

    @Test func realKeyAndFeedTurnItOn() {
        let config = UpdaterConfiguration(info: ["SUFeedURL": feed, "SUPublicEDKey": "abc123="])
        #expect(config.isEnabled)
        #expect(config.feedURL?.absoluteString == feed)
    }

    @Test func shippedInfoPlistUsesTheReleasesFeed() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Resources/Info.plist")
        let info = try #require(NSDictionary(contentsOf: url) as? [String: Any])
        #expect(info["SUFeedURL"] as? String == feed)
        #expect(info["SUEnableInstallerLauncherService"] as? Bool == false)
        #expect(info["CFBundleShortVersionString"] as? String == ScreenCapKit.version)
        #expect(info["SUPublicEDKey"] is String)
    }
}

@Suite("Welcome window")
@MainActor
struct WelcomePolicyTests {
    @Test func missingPermissionAlwaysShows() {
        #expect(WelcomePolicy.showAtLaunch(permissionGranted: false, dontShowAgain: true))
        #expect(WelcomePolicy.showAtLaunch(permissionGranted: false, dontShowAgain: false))
    }

    @Test func grantedShowsUntilDismissedForGood() {
        #expect(WelcomePolicy.showAtLaunch(permissionGranted: true, dontShowAgain: false))
        #expect(!WelcomePolicy.showAtLaunch(permissionGranted: true, dontShowAgain: true))
    }

    @Test func teachesAreaWindowFullscreen() {
        #expect(WelcomePolicy.mainShortcuts.map(\.title) == ["Capture Area", "Capture Window", "Capture Fullscreen"])
    }
}

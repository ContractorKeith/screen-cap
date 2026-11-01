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

    /// #135: the shipped plist's own key value, through the real check. If the plist text drifts from
    /// `placeholderKey`, Sparkle would start with a junk key; this fails first. When a real key lands,
    /// flip this to `isEnabled` and delete the placeholder.
    @Test func shippedInfoPlistKeepsTheUpdaterOff() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Resources/Info.plist")
        let info = try #require(NSDictionary(contentsOf: url) as? [String: Any])
        let config = UpdaterConfiguration(info: info)
        #expect(config.feedURL != nil) // so it's the key, not a missing feed, that keeps it off
        #expect(!config.isEnabled)
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

@Suite("Re-grant after update (#141)")
struct PermissionRegrantTests {
    @Test func deniedAfterAnEarlierBuildHadItIsAnUpdate() {
        #expect(PermissionRegrant.wasUpdated(granted: false, grantedBuild: "52", currentBuild: "53"))
    }

    @Test func firstRunAndSameBuildAreNotUpdates() {
        #expect(!PermissionRegrant.wasUpdated(granted: false, grantedBuild: nil, currentBuild: "53"))
        #expect(!PermissionRegrant.wasUpdated(granted: false, grantedBuild: "53", currentBuild: "53"))
        #expect(!PermissionRegrant.wasUpdated(granted: true, grantedBuild: "52", currentBuild: "53"))
    }

    @Test func recordsOnlyWhenGranted() {
        let suite = TemporaryDefaults()
        defer { suite.remove() }
        PermissionRegrant.record(granted: false, defaults: suite.store)
        #expect(suite.store.string(forKey: PermissionRegrant.grantedBuildKey) == nil)
        PermissionRegrant.record(granted: true, defaults: suite.store)
        #expect(suite.store.string(forKey: PermissionRegrant.grantedBuildKey) == PermissionRegrant.currentBuild)
    }

    @Test func resetCommandTargetsThisApp() {
        #expect(PermissionRegrant.resetCommand == "tccutil reset ScreenCapture com.contractorkeith.screencap")
    }
}

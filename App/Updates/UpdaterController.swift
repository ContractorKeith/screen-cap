import AppKit
import ScreenCapKit
@preconcurrency import Sparkle

/// Reads the Sparkle keys from Info.plist. Pure, so the "skip when unconfigured" rule is testable.
struct UpdaterConfiguration: Equatable {
    /// Committed in Info.plist until a real key is generated with Sparkle's `generate_keys`.
    static let placeholderKey = "REPLACE_WITH_SUPublicEDKey_FROM_generate_keys"
    static let releasesURL = ScreenCapKit.repositoryURL.appendingPathComponent("releases")

    var feedURL: URL?
    var publicKey: String?

    init(info: [String: Any]) {
        feedURL = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))
        publicKey = info["SUPublicEDKey"] as? String
    }

    /// Sparkle refuses unsigned updates, so it only runs with a feed and a real EdDSA public key.
    var isEnabled: Bool {
        guard feedURL != nil, let key = publicKey?.trimmingCharacters(in: .whitespaces) else { return false }
        return !key.isEmpty && key != Self.placeholderKey
    }
}

/// Owns Sparkle. When the bundle has no real update key (dev builds, placeholder in Info.plist),
/// Sparkle never starts and "Check for Updates…" opens the GitHub releases page instead.
@MainActor
final class UpdaterController {
    let configuration: UpdaterConfiguration
    private let sparkle: SPUStandardUpdaterController?

    init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        configuration = UpdaterConfiguration(info: info)
        if configuration.isEnabled {
            sparkle = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        } else {
            sparkle = nil
            appLog.notice("Updater off: SUPublicEDKey is not set; Check for Updates opens the releases page")
        }
    }

    var isEnabled: Bool { sparkle != nil }

    /// Background checks; Sparkle persists this in UserDefaults (`SUEnableAutomaticChecks`).
    var automaticallyChecksForUpdates: Bool {
        get { sparkle?.updater.automaticallyChecksForUpdates ?? false }
        set { sparkle?.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        if let sparkle {
            NSApp.activate(ignoringOtherApps: true)
            sparkle.checkForUpdates(nil)
        } else {
            NSWorkspace.shared.open(UpdaterConfiguration.releasesURL)
        }
    }
}

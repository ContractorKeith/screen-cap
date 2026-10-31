import Foundation
import Observation
import SwiftUI

/// Scrolling capture preferences. Kept app-side in their own UserDefaults keys so this
/// feature doesn't touch the shared `AppSettings` schema.
@MainActor
@Observable
final class ScrollingSettings {
    enum Defaults {
        static let autoScroll = false
        /// Points per auto-scroll step.
        static let scrollStep = 120
        static let frameRate = 12
        /// Stitched length cap in points along the scroll axis.
        static let maxLength = 20_000
        static let horizontal = false

        static let scrollStepChoices = [60, 120, 200, 300]
        static let frameRateChoices = [6, 12, 20, 30]
        static let maxLengthChoices = [5_000, 10_000, 20_000, 40_000]
    }

    private enum Key: String {
        case autoScroll = "scrolling.autoScroll"
        case scrollStep = "scrolling.scrollStep"
        case frameRate = "scrolling.frameRate"
        case maxLength = "scrolling.maxLength"
        case horizontal = "scrolling.horizontal"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var autoScroll: Bool { didSet { defaults.set(autoScroll, forKey: Key.autoScroll.rawValue) } }
    var scrollStep: Int { didSet { defaults.set(scrollStep, forKey: Key.scrollStep.rawValue) } }
    var frameRate: Int { didSet { defaults.set(frameRate, forKey: Key.frameRate.rawValue) } }
    var maxLength: Int { didSet { defaults.set(maxLength, forKey: Key.maxLength.rawValue) } }
    var horizontal: Bool { didSet { defaults.set(horizontal, forKey: Key.horizontal.rawValue) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func int(_ key: Key, _ fallback: Int) -> Int {
            let value = defaults.integer(forKey: key.rawValue)
            return value > 0 ? value : fallback
        }
        func bool(_ key: Key, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key.rawValue) == nil ? fallback : defaults.bool(forKey: key.rawValue)
        }
        autoScroll = bool(.autoScroll, Defaults.autoScroll)
        scrollStep = int(.scrollStep, Defaults.scrollStep)
        frameRate = int(.frameRate, Defaults.frameRate)
        maxLength = int(.maxLength, Defaults.maxLength)
        horizontal = bool(.horizontal, Defaults.horizontal)
    }

    /// Time between frame grabs.
    var frameInterval: Duration { .milliseconds(1000 / max(1, min(frameRate, 60))) }
}

/// Settings tab for scrolling capture.
struct ScrollingSettingsPane: View {
    @Bindable var settings: ScrollingSettings

    var body: some View {
        Form {
            Section {
                Toggle("Auto-scroll by default", isOn: $settings.autoScroll)
                Toggle("Scroll horizontally by default", isOn: $settings.horizontal)
            } footer: {
                Text("Auto-scroll needs Accessibility permission; you're asked the first time it's used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Scroll step", selection: $settings.scrollStep) {
                    ForEach(ScrollingSettings.Defaults.scrollStepChoices, id: \.self) { Text("\($0) pt").tag($0) }
                }
                Picker("Frame rate", selection: $settings.frameRate) {
                    ForEach(ScrollingSettings.Defaults.frameRateChoices, id: \.self) { Text("\($0) fps").tag($0) }
                }
                Picker("Max length", selection: $settings.maxLength) {
                    ForEach(ScrollingSettings.Defaults.maxLengthChoices, id: \.self) {
                        Text("\($0.formatted()) pt").tag($0)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

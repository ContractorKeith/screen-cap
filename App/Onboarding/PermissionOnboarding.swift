import AppKit
import CoreGraphics
@preconcurrency import KeyboardShortcuts
import SwiftUI

/// Screen Recording (TCC) permission checks.
enum ScreenRecordingPermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!

    /// Registers the app in the Screen Recording list (shows the system prompt once), then opens the pane.
    static func openSystemSettings() {
        _ = CGRequestScreenCaptureAccess()
        NSWorkspace.shared.open(settingsURL)
    }
}

/// Ad-hoc builds lose Screen Recording on update (#141): System Settings keeps the old
/// ScreenCap toggle on, but it no longer matches the new app. Pure so the rule is testable.
enum PermissionRegrant {
    /// The `CFBundleVersion` that last had permission.
    static let grantedBuildKey = "permission.grantedBuild"
    /// Clears the stale entries. The user runs it in Terminal; then Open System Settings adds a fresh one.
    static let resetCommand = "tccutil reset ScreenCapture com.contractorkeith.screencap"

    static var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    /// True when an earlier build had permission and this one doesn't: an update, not a first run.
    static func wasUpdated(granted: Bool, grantedBuild: String?, currentBuild: String) -> Bool {
        guard !granted, let grantedBuild else { return false }
        return grantedBuild != currentBuild
    }

    /// Remembers the build that has permission, so the next update can be recognized.
    static func record(granted: Bool, defaults: UserDefaults = .standard) {
        if granted { defaults.set(currentBuild, forKey: grantedBuildKey) }
    }

    static func updatedSinceGrant(defaults: UserDefaults = .standard) -> Bool {
        wasUpdated(
            granted: ScreenRecordingPermission.isGranted,
            grantedBuild: defaults.string(forKey: grantedBuildKey),
            currentBuild: currentBuild
        )
    }
}

/// Polls permission state once a second while the onboarding window is visible.
@MainActor
@Observable
final class PermissionModel {
    var isGranted = ScreenRecordingPermission.isGranted
    /// An earlier build had permission; this one needs it re-granted (#141).
    var updatedSinceGrant = PermissionRegrant.updatedSinceGrant()
    private var timer: Timer?

    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        isGranted = ScreenRecordingPermission.isGranted
        PermissionRegrant.record(granted: isGranted)
        if isGranted { stopPolling() }
    }
}

/// When the welcome window opens at launch. Pure so the rule is testable.
enum WelcomePolicy {
    static let dontShowAgainKey = "welcome.dontShowAgain"

    /// Missing permission always shows it (nothing works without it); otherwise until the user opts out.
    static func showAtLaunch(permissionGranted: Bool, dontShowAgain: Bool) -> Bool {
        !permissionGranted || !dontShowAgain
    }

    /// Unnotarized builds (#128): each new download is blocked once; macOS 15 removed right-click → Open.
    static let blockedAppHint = """
        If macOS blocked the app (or blocks a new version): System Settings → Privacy & Security → \
        Open Anyway. On macOS 14, right-click ScreenCap → Open.
        """

    /// The three shortcuts the welcome step teaches, in order.
    @MainActor static let mainShortcuts: [ShortcutCatalog.Entry] = ShortcutCatalog.all.filter {
        [.captureArea, .captureWindow, .captureFullscreen].contains($0.name)
    }
}

/// Step 1 asks for Screen Recording; once granted, step 2 teaches the main shortcuts.
struct PermissionOnboardingView: View {
    let model: PermissionModel
    let close: () -> Void
    let takeFirstScreenshot: () -> Void
    @AppStorage(WelcomePolicy.dontShowAgainKey) private var dontShowAgain = false

    var body: some View {
        Group {
            if model.isGranted { shortcutsStep } else { permissionStep }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                model.updatedSinceGrant ? "ScreenCap was updated" : "Screen Recording access",
                systemImage: "rectangle.dashed.badge.record"
            )
            .font(.title2.bold())
            Text(model.updatedSinceGrant ? """
                macOS needs the Screen Recording permission re-granted for the new version. \
                The old ScreenCap toggle in System Settings may still show on, but it no longer applies.
                """ : """
                ScreenCap needs Screen Recording permission to capture your screen. \
                Images stay on this Mac. Turn on ScreenCap in System Settings → \
                Privacy & Security → Screen & System Audio Recording.
                """)
                .fixedSize(horizontal: false, vertical: true)
            regrantSteps
            Label("Waiting for permission…", systemImage: "hourglass")
                .foregroundStyle(.secondary)
            Text("macOS may ask you to quit and reopen ScreenCap after you turn it on.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(WelcomePolicy.blockedAppHint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Later", action: close)
                Button("Open System Settings") { ScreenRecordingPermission.openSystemSettings() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// Clearing the stale entry: shown expanded after an update, as a one-line hint otherwise.
    private var regrantSteps: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.updatedSinceGrant
                 ? "1. Copy this command, paste it in Terminal and press Return:"
                 : "Toggle already on? Updates need it again. Run this in Terminal:")
                .font(model.updatedSinceGrant ? .body : .footnote)
            HStack {
                Text(PermissionRegrant.resetCommand)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                Spacer()
                Button("Copy Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(PermissionRegrant.resetCommand, forType: .string)
                }
            }
            Text(model.updatedSinceGrant
                 ? "2. Click Open System Settings and turn ScreenCap on."
                 : "Then click Open System Settings and turn ScreenCap on.")
                .font(model.updatedSinceGrant ? .body : .footnote)
        }
    }

    private var shortcutsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("You're ready to capture", systemImage: "checkmark.circle.fill")
                .font(.title2.bold())
                .foregroundStyle(.green)
            Text("ScreenCap lives in the menu bar. These work from any app:")
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                ForEach(WelcomePolicy.mainShortcuts, id: \.name.rawValue) { entry in
                    GridRow {
                        Text(entry.title)
                        let shortcut = KeyboardShortcuts.getShortcut(for: entry.name)?.description ?? "Not set"
                        Text(shortcut)
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(A11y.spokenShortcut(shortcut))
                    }
                }
            }
            Text("Change them in Settings → Shortcuts. The menu bar icon has every capture mode.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Toggle("Don't show again", isOn: $dontShowAgain)
                Spacer()
                Button("Done", action: close)
                Button("Take Your First Screenshot", action: takeFirstScreenshot)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

@MainActor
final class PermissionOnboardingController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model = PermissionModel()
    /// Runs the area capture; set by `AppDelegate` once the coordinator exists.
    var firstCapture: @MainActor () -> Void = {}

    var shouldShowAtLaunch: Bool {
        WelcomePolicy.showAtLaunch(
            permissionGranted: ScreenRecordingPermission.isGranted,
            dontShowAgain: UserDefaults.standard.bool(forKey: WelcomePolicy.dontShowAgainKey)
        )
    }

    func show() {
        if window == nil {
            let view = PermissionOnboardingView(
                model: model,
                close: { [weak self] in self?.window?.close() },
                takeFirstScreenshot: { [weak self] in self?.startFirstCapture() }
            )
            let newWindow = NSWindow(contentViewController: NSHostingController(rootView: view))
            newWindow.title = "Welcome to ScreenCap"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self
            // Sized to its content before centering, so it opens centered and on screen (#115).
            WindowPlacement.placeNew(newWindow, autosaveName: "ScreenCapWelcomeWindow")
            window = newWindow
        } else if let window {
            WindowPlacement.clampOnScreen(window)
        }
        model.startPolling()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.stopPolling()
    }

    /// Closes the window first so it isn't frozen into the selection overlay.
    private func startFirstCapture() {
        window?.close()
        Task { @MainActor [firstCapture] in
            try? await Task.sleep(for: .milliseconds(300))
            firstCapture()
        }
    }
}

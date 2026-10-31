import AppKit
import CoreGraphics
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

/// Polls permission state once a second while the onboarding window is visible.
@MainActor
@Observable
final class PermissionModel {
    var isGranted = ScreenRecordingPermission.isGranted
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
        if isGranted { stopPolling() }
    }
}

struct PermissionOnboardingView: View {
    let model: PermissionModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Screen Recording access", systemImage: "rectangle.dashed.badge.record")
                .font(.title2.bold())
            Text("""
                ScreenCap needs Screen Recording permission to capture your screen. \
                Images stay on this Mac. Turn on ScreenCap in System Settings → \
                Privacy & Security → Screen & System Audio Recording.
                """)
                .fixedSize(horizontal: false, vertical: true)
            if model.isGranted {
                Label("Permission granted. You're ready to capture.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Waiting for permission…", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
                Text("macOS may ask you to quit and reopen ScreenCap after you turn it on.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                if model.isGranted {
                    Button("Done", action: close).keyboardShortcut(.defaultAction)
                } else {
                    Button("Later", action: close)
                    Button("Open System Settings") { ScreenRecordingPermission.openSystemSettings() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

@MainActor
final class PermissionOnboardingController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model = PermissionModel()

    func show() {
        if window == nil {
            let view = PermissionOnboardingView(model: model) { [weak self] in self?.window?.close() }
            let newWindow = NSWindow(contentViewController: NSHostingController(rootView: view))
            newWindow.title = "Welcome to ScreenCap"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self
            newWindow.center()
            window = newWindow
        }
        model.startPolling()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.stopPolling()
    }
}

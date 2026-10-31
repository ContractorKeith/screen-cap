import AppKit
import ScreenCapKit

/// The live `AutomationHandling`: the capture coordinator, Settings, desktop icons and HUD.
@MainActor
final class AppAutomationHandler: AutomationHandling {
    private let coordinator: CaptureCoordinator
    private let settingsWindow: SettingsWindowController
    private let desktopIconsController: DesktopIconsController

    init(coordinator: CaptureCoordinator, settingsWindow: SettingsWindowController,
         desktopIcons: DesktopIconsController) {
        self.coordinator = coordinator
        self.settingsWindow = settingsWindow
        self.desktopIconsController = desktopIcons
    }

    /// Scripts fire captures back to back, so these queue behind a running one (#79).
    func capture(_ kind: CaptureKind, rect: CGRect?, action: AfterCaptureAction?) {
        if let rect {
            coordinator.capture(kind, rect: rect, action: action, queueIfBusy: true)
        } else {
            coordinator.capture(kind, action: action, queueIfBusy: true)
        }
    }

    func captureText(rect: CGRect, lineBreaks: Bool) {
        coordinator.captureText(rect: rect, lineBreaks: lineBreaks, queueIfBusy: true)
    }

    /// The scrolling feature starts its own capture from `.scrollingCaptureRequested`, so the
    /// request itself waits for the queue (#102). Observers on the main queue run synchronously.
    func scrollingCapture(rect: CGRect, start: Bool, autoscroll: Bool) {
        let info: [String: Any] = [
            AutomationKey.rect: NSValue(rect: rect), AutomationKey.start: start, AutomationKey.autoscroll: autoscroll
        ]
        coordinator.whenIdle("scrolling at \(rect)") { [weak self] in
            self?.post(.scrollingCaptureRequested, userInfo: info)
        }
    }

    func post(_ name: Notification.Name, userInfo: [String: Any]) {
        appLog.notice("URL scheme posting \(name.rawValue, privacy: .public)")
        NotificationCenter.default.post(name: name, object: self, userInfo: userInfo.isEmpty ? nil : userInfo)
    }

    /// Writes the clipboard image to a temp PNG and opens it in the editor.
    func openFromClipboard() {
        guard let url = ClipboardImage.writeTemporaryPNG(from: .general) else {
            showError("There's no image on the clipboard.")
            return
        }
        post(.openAnnotateRequested, userInfo: [AutomationKey.url: url])
    }

    func openSettings(tab: AutomationCommand.SettingsTab?) {
        settingsWindow.show(tab: tab)
    }

    func desktopIcons(_ change: DesktopIconsController.Change) {
        desktopIconsController.apply(change)
    }

    func showError(_ message: String) {
        appLog.error("URL scheme error: \(message, privacy: .public)")
        AutomationHUD.show(title: "ScreenCap couldn't run that link", message: message)
    }
}

/// Reads an image from a pasteboard into a temporary PNG file.
enum ClipboardImage {
    static func writeTemporaryPNG(from pasteboard: NSPasteboard) -> URL? {
        guard let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ScreenCap", isDirectory: true)
        let url = folder.appendingPathComponent("Clipboard \(UUID().uuidString.prefix(8)).png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
            return url
        } catch {
            appLog.error("Clipboard image write failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

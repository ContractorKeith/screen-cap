import AppKit
import ScreenCapKit

// Split out of ScrollingCaptureController to keep its body under the lint limit.
extension ScrollingCaptureController {
    func showAccessibilitySheet() {
        let alert = NSAlert()
        alert.messageText = "Auto-scroll needs Accessibility access"
        alert.informativeText = """
            ScreenCap scrolls the page for you by sending scroll events, which macOS allows only for apps \
            with Accessibility access. Turn on ScreenCap in System Settings → Privacy & Security → \
            Accessibility, then start a new scrolling capture. This capture continues manually: scroll the \
            region yourself.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Continue Manually")
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            // Registers the app in the Accessibility list so the user only has to flip the switch.
            let prompt = "AXTrustedCheckOptionPrompt" as CFString
            _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
        if let controlPanel {
            alert.beginSheetModal(for: controlPanel, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    // MARK: - Panels

}

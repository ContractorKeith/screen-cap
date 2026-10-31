import AppKit
import SwiftUI

/// A small non-activating panel near the top of the screen that fades out by itself.
/// Used for URL scheme errors so a script never blocks on a modal alert.
@MainActor
enum AutomationHUD {
    private static var panel: NSPanel?
    private static var dismissal: Task<Void, Never>?
    static let visibleDuration = Duration.seconds(5)

    static func show(title: String, message: String) {
        dismissal?.cancel()
        panel?.orderOut(nil)
        let view = HUDView(title: title, message: message) { hide() }
        let hosting = NSHostingView(rootView: view)
        hosting.frame.size = hosting.fittingSize
        let newPanel = NSPanel(contentRect: hosting.frame, styleMask: [.nonactivatingPanel, .borderless],
                               backing: .buffered, defer: false)
        newPanel.contentView = hosting
        newPanel.isFloatingPanel = true
        newPanel.level = .statusBar
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            newPanel.setFrameTopLeftPoint(CGPoint(x: frame.midX - hosting.frame.width / 2, y: frame.maxY - 12))
        }
        newPanel.orderFrontRegardless()
        panel = newPanel
        dismissal = Task {
            try? await Task.sleep(for: visibleDuration)
            if !Task.isCancelled { hide() }
        }
    }

    static func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct HUDView: View {
    let title: String
    let message: String
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Button(action: close) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 420, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

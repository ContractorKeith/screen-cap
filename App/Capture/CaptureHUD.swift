import AppKit
import ScreenCapKit

/// A rounded panel near the top of the screen for capture problems, with up to a few buttons.
/// It fades out on its own (longer when it offers actions); a new one replaces the visible one.
@MainActor
final class CaptureHUD: NSObject {
    struct Button {
        let title: String
        let action: @MainActor () -> Void
    }

    private static var current: CaptureHUD?
    private let panel: NSPanel
    private let buttons: [Button]
    private var dismissTask: Task<Void, Never>?

    static func show(_ message: String, detail: String? = nil, buttons: [Button] = []) {
        current?.close()
        let hud = CaptureHUD(message: message, detail: detail, buttons: buttons)
        current = hud
        hud.present(for: buttons.isEmpty ? .seconds(4) : .seconds(10))
    }

    private init(message: String, detail: String?, buttons: [Button]) {
        self.buttons = buttons
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        super.init()
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.contentView = makeContent(message: message, detail: detail)
        panel.setContentSize(panel.contentView?.fittingSize ?? .zero)
    }

    private func makeContent(message: String, detail: String?) -> NSView {
        let title = NSTextField(labelWithString: message)
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        var texts: [NSView] = [title]
        if let detail {
            let label = NSTextField(wrappingLabelWithString: detail)
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            label.preferredMaxLayoutWidth = 360
            texts.append(label)
        }
        let column = NSStackView(views: texts)
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 2
        var row: [NSView] = [column]
        for (index, button) in buttons.enumerated() {
            let control = NSButton(title: button.title, target: self, action: #selector(buttonPressed(_:)))
            control.bezelStyle = .rounded
            control.tag = index
            row.append(control)
        }
        let stack = NSStackView(views: row)
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 18, bottom: 10, right: 14)

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])
        return effect
    }

    private func present(for duration: Duration) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 40))
        }
        panel.orderFrontRegardless()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    private func close() {
        dismissTask?.cancel()
        panel.orderOut(nil)
        if Self.current === self { Self.current = nil }
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        guard buttons.indices.contains(sender.tag) else { return }
        buttons[sender.tag].action()
        close()
    }
}

/// User-facing messages for capture problems (#47). Everything here also goes to the log.
@MainActor
enum CaptureFailureHUD {
    /// A capture flow threw before anything was delivered.
    static func showCaptureFailed(_ error: Error) {
        CaptureHUD.show("Capture failed", detail: error.localizedDescription)
    }

    /// A shortcut arrived while another capture or the self-timer was running.
    static func showBusy() {
        CaptureHUD.show("A capture is already in progress", detail: "Finish or cancel it, then try again.")
    }

    /// Saving or copying failed after the capture itself worked; offers a way to get at the image.
    static func showOutputFailed(_ action: AfterCaptureAction, error: Error, result: CaptureResult,
                                 output: CaptureOutput) {
        var buttons: [CaptureHUD.Button] = []
        if action != .copy {
            buttons.append(.init(title: "Copy to Clipboard") {
                Task {
                    do {
                        try await output.copy(result)
                        CaptureHUD.show("Copied to the clipboard")
                    } catch {
                        CaptureHUD.show("Couldn't copy the capture", detail: error.localizedDescription)
                    }
                }
            })
        }
        if let url = result.historyFileURL {
            buttons.append(.init(title: "Reveal History Copy") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            })
        }
        let message = action == .copy
            ? "Couldn't copy the capture"
            : "Couldn't save to \(output.saveFolder.lastPathComponent)"
        CaptureHUD.show(message, detail: error.localizedDescription, buttons: buttons)
    }
}

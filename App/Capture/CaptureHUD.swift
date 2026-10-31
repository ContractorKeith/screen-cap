import AppKit
import ScreenCapKit

/// Which visible HUDs a new one replaces (#78). A HUD with buttons may be the only way to recover
/// a capture (Copy to Clipboard), so it stays and the new one stacks below it; plain messages are
/// replaced. At most `maxVisible` stay up; past that the oldest goes.
enum CaptureHUDStack {
    static let maxVisible = 4

    /// Indices (oldest first) of visible HUDs to keep when a new one appears.
    static func kept(hasButtons: [Bool]) -> [Int] {
        let actionable = hasButtons.indices.filter { hasButtons[$0] }
        return Array(actionable.suffix(maxVisible - 1))
    }
}

/// A rounded panel near the top of the screen for capture problems, with up to a few buttons.
/// It fades out on its own (longer when it offers actions). A new one replaces plain messages and
/// stacks below ones that still offer an action (`CaptureHUDStack`).
@MainActor
final class CaptureHUD: NSObject {
    struct Button {
        let title: String
        let action: @MainActor () -> Void
    }

    /// On screen, oldest first (top of the stack).
    private static var visible: [CaptureHUD] = []
    private let panel: NSPanel
    private let buttons: [Button]
    private var dismissTask: Task<Void, Never>?

    static func show(_ message: String, detail: String? = nil, buttons: [Button] = []) {
        let keep = Set(CaptureHUDStack.kept(hasButtons: visible.map { !$0.buttons.isEmpty }))
        for (index, hud) in visible.enumerated() where !keep.contains(index) { hud.close() }
        let hud = CaptureHUD(message: message, detail: detail, buttons: buttons)
        visible.append(hud)
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
        if let frame = screen?.visibleFrame {
            // Below any HUD still showing an action.
            let above = Self.visible.filter { $0 !== self }.map(\.panel.frame.minY).min()
            let top = above.map { $0 - 8 } ?? frame.maxY - 40
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: top - size.height))
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
        Self.visible.removeAll { $0 === self }
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

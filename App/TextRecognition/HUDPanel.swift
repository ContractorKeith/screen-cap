import AppKit

/// A small rounded panel near the top of the screen that fades out on its own.
/// Optional button (used for "Open" on scanned links).
@MainActor
final class HUDPanel {
    private static var current: HUDPanel?
    private let panel: NSPanel
    private var buttonAction: (() -> Void)?
    private var dismissTask: Task<Void, Never>?

    /// Shows `message`; a new HUD replaces the visible one.
    static func show(_ message: String, buttonTitle: String? = nil, duration: Duration = .seconds(2),
                     action: (() -> Void)? = nil) {
        current?.close()
        let hud = HUDPanel(message: message, buttonTitle: buttonTitle, action: action)
        current = hud
        hud.present(for: buttonTitle == nil ? duration : duration * 2)
    }

    private init(message: String, buttonTitle: String?, action: (() -> Void)?) {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        buttonAction = action

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .labelColor
        var views: [NSView] = [label]
        if let buttonTitle {
            let button = NSButton(title: buttonTitle, target: nil, action: nil)
            button.bezelStyle = .rounded
            button.target = self
            button.action = #selector(buttonPressed)
            views.append(button)
        }
        let stack = NSStackView(views: views)
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)

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
        panel.contentView = effect
        panel.setContentSize(stack.fittingSize)
    }

    private func present(for duration: Duration) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 40))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.fadeOut()
        }
    }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in self?.close() }
        })
    }

    private func close() {
        dismissTask?.cancel()
        panel.orderOut(nil)
        if Self.current === self { Self.current = nil }
    }

    @objc private func buttonPressed() {
        buttonAction?()
        close()
    }
}

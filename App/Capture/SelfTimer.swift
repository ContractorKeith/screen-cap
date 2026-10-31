import AppKit

/// Countdown state for the self-timer. Pure, so it is unit-tested.
struct CountdownState: Equatable {
    let total: Int
    private(set) var remaining: Int

    /// At least one second.
    init(seconds: Int) {
        total = max(1, seconds)
        remaining = total
    }

    var isFinished: Bool { remaining == 0 }

    /// 0 at the start, 1 when finished.
    var progress: Double { Double(total - remaining) / Double(total) }

    mutating func tick() {
        if remaining > 0 { remaining -= 1 }
    }
}

/// Shows an on-screen countdown badge. Clicking the badge cancels.
@MainActor
final class SelfTimer {
    private var panel: NSPanel?
    private var cancelled = false

    /// Counts down centered on `rect` (global points) or the screen under the cursor.
    /// Returns false if the user cancelled.
    func countdown(seconds: Int, around rect: CGRect?) async -> Bool {
        var state = CountdownState(seconds: seconds)
        cancelled = false
        let badge = CountdownBadgeView { [weak self] in self?.cancelled = true }
        show(badge, around: rect)
        defer { hide() }
        while !state.isFinished {
            badge.value = state.remaining
            try? await Task.sleep(for: .seconds(1))
            if cancelled || Task.isCancelled { return false }
            state.tick()
        }
        return true
    }

    private func show(_ badge: NSView, around rect: CGRect?) {
        let size = CGSize(width: 120, height: 120)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let center = rect.map { CGPoint(x: $0.midX, y: $0.midY) }
            ?? screen.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) } ?? .zero
        let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                           width: size.width, height: size.height)
        let panel = OverlayPanel(frame: frame)
        panel.contentView = badge
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

/// Big rounded number. Our own windows are excluded from captures, so it never shows up in one.
final class CountdownBadgeView: NSView {
    var value = 0 { didSet { needsDisplay = true } }
    private let onClick: () -> Void

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 24, yRadius: 24).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 64, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let text = "\(value)" as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                  withAttributes: attributes)
    }
}

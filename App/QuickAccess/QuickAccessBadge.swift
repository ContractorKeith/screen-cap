import AppKit

/// "+N" pill shown when more Quick Access panels are open than fit on screen (#116).
/// The hidden panels come back, newest first, as visible ones close.
final class QuickAccessBadge: NSPanel {
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(contentRect: CGRect(origin: .zero, size: QuickAccessLayout.badgeSize),
                   styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false

        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: QuickAccessLayout.badgeSize))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = QuickAccessLayout.badgeSize.height / 2
        background.layer?.masksToBounds = true
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.alignment = .center
        label.frame = background.bounds.insetBy(dx: 4, dy: 4)
        label.autoresizingMask = [.width, .height]
        background.addSubview(label)
        contentView = background
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setCount(_ count: Int) {
        label.stringValue = "+\(count)"
        let noun = count == 1 ? "capture" : "captures"
        contentView?.toolTip = "\(count) more \(noun). Close a panel to see the next one."
    }
}

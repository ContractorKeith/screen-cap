import AppKit

/// One floating Quick Access thumbnail. Never becomes key, so it never takes focus from
/// the app the user is working in; shows on every Space and over full-screen apps.
final class QuickAccessPanel: NSPanel {
    let thumbnail: QuickAccessThumbnailView
    private let dimensionsLabel = QuickAccessPanel.label(size: 11, weight: .medium, color: .labelColor)
    private let nameLabel = QuickAccessPanel.label(size: 10, weight: .regular, color: .secondaryLabelColor)

    init(image: CGImage, size: CGSize) {
        thumbnail = QuickAccessThumbnailView(image: image)
        super.init(contentRect: CGRect(origin: .zero, size: size),
                   styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        contentView = makeContent(size: size)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Two-line info under the thumbnail: dimensions (plus file size once saved), then the
    /// filename or a status message.
    func setInfo(dimensions: String, name: String) {
        dimensionsLabel.stringValue = dimensions
        nameLabel.stringValue = name
        nameLabel.toolTip = name
    }

    private func makeContent(size: CGSize) -> NSView {
        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true

        let pad = QuickAccessLayout.padding
        let info = QuickAccessLayout.infoHeight
        thumbnail.frame = CGRect(x: pad, y: pad + info, width: size.width - 2 * pad,
                                 height: size.height - 2 * pad - info)
        thumbnail.autoresizingMask = [.width, .height]
        background.addSubview(thumbnail)

        let labels = NSStackView(views: [dimensionsLabel, nameLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1
        labels.frame = CGRect(x: pad + 2, y: pad - 1, width: size.width - 2 * pad - 4, height: info)
        labels.autoresizingMask = [.width]
        background.addSubview(labels)
        return background
    }

    private static func label(size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
}

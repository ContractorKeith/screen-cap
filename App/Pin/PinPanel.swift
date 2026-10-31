import AppKit

/// What a pin asks its controller to do (context menu and shortcuts).
enum PinCommand {
    case copy, save, annotate, toggleLock, close
}

/// One floating screenshot: always on top, every Space, above full-screen apps.
///
/// Keys when focused: ⌘+/⌘− zoom, ⌘[/⌘] opacity, arrows nudge (⇧ ×10), ⌘L lock, ⌘C copy,
/// ⌘W or Esc close. Double-click toggles 100% and fit; edge drags keep the aspect ratio.
@MainActor
final class PinPanel: NSPanel, NSWindowDelegate {
    /// The image's size at 1x, in points.
    let pointSize: CGSize
    private(set) var lockState = PinLockState.interactive
    private let imageView: PinImageView
    var onCommand: ((PinPanel, PinCommand) -> Void)?
    var onFrameChange: ((PinPanel) -> Void)?

    init(image: CGImage, pointSize: CGSize, frame: NSRect) {
        self.pointSize = pointSize
        imageView = PinImageView(image: image)
        super.init(contentRect: frame, styleMask: [.borderless, .resizable, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = true
        delegate = self
        contentView = imageView
        imageView.panel = self
    }

    override var canBecomeKey: Bool { lockState.acceptsKeyboard }
    override var canBecomeMain: Bool { false }

    // MARK: Size and zoom

    var scale: CGFloat { PinMath.scale(of: frame.size, pointSize: pointSize) }

    /// Resizes to `scale` × 1x, keeping the top-left corner where it is.
    func setScale(_ scale: CGFloat, animate: Bool = false) {
        let size = PinMath.size(for: pointSize, scale: scale)
        let frame = NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
        setFrame(frame, display: true, animate: animate)
    }

    func zoom(steps: Int) {
        setScale(PinMath.zoomed(scale, steps: steps, pointSize: pointSize))
    }

    func toggleActualSize() {
        let visible = (screen ?? NSScreen.main)?.visibleFrame.size ?? pointSize
        let fit = PinMath.fitScale(pointSize: pointSize, visibleFrame: visible)
        setScale(PinMath.doubleClickScale(current: scale, fitScale: fit), animate: true)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        PinMath.aspectResize(current: frame.size, proposed: frameSize, pointSize: pointSize)
    }

    func windowDidMove(_ notification: Notification) { onFrameChange?(self) }
    func windowDidResize(_ notification: Notification) { onFrameChange?(self) }

    // MARK: Opacity, nudge, lock

    func stepOpacity(_ steps: Int) {
        alphaValue = PinMath.opacity(Double(alphaValue), steps: steps)
    }

    func nudge(_ arrow: PinMath.Arrow, shift: Bool) {
        let delta = PinMath.nudge(arrow, shift: shift)
        setFrameOrigin(NSPoint(x: frame.minX + delta.dx, y: frame.minY + delta.dy))
    }

    func apply(_ event: PinLockState.Event) {
        lockState = lockState.handling(event)
        ignoresMouseEvents = lockState.ignoresMouseEvents
        imageView.showsLockBorder = lockState.showsLockBorder
        if !lockState.acceptsKeyboard, isKeyWindow { resignKey() }
    }

    // MARK: Keys

    /// Handles a key; returns false if it isn't a pin shortcut.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53 { // Esc
            onCommand?(self, .close)
            return true
        }
        if let arrow = Self.arrows[event.keyCode] {
            nudge(arrow, shift: flags.contains(.shift))
            return true
        }
        guard flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased(),
              let action = Self.commandKeys[key] else { return false }
        action(self)
        return true
    }

    private static let arrows: [UInt16: PinMath.Arrow] = [123: .left, 124: .right, 125: .down, 126: .up]

    /// ⌘-key shortcuts by `charactersIgnoringModifiers`.
    private static let commandKeys: [String: @MainActor (PinPanel) -> Void] = [
        "=": { $0.zoom(steps: 1) }, "+": { $0.zoom(steps: 1) },
        "-": { $0.zoom(steps: -1) }, "_": { $0.zoom(steps: -1) },
        "[": { $0.stepOpacity(-1) }, "]": { $0.stepOpacity(1) },
        "l": { $0.onCommand?($0, .toggleLock) }, "c": { $0.onCommand?($0, .copy) },
        "s": { $0.onCommand?($0, .save) }, "w": { $0.onCommand?($0, .close) }
    ]

    // MARK: Context menu

    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        let rows: [(String, PinCommand)] = [
            ("Copy", .copy), ("Save", .save), ("Annotate", .annotate),
            ("Lock", .toggleLock), ("Close", .close)
        ]
        for (title, command) in rows {
            if command == .close { menu.addItem(.separator()) }
            let item = NSMenuItem(title: title, action: #selector(menuCommand(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = command
            menu.addItem(item)
        }
        return menu
    }

    @objc private func menuCommand(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? PinCommand else { return }
        onCommand?(self, command)
    }
}

/// Draws the pinned image scaled to fill, with an optional Lock Mode border.
@MainActor
final class PinImageView: NSView {
    weak var panel: PinPanel?
    private let border = CALayer()

    var showsLockBorder = false {
        didSet { border.isHidden = !showsLockBorder }
    }

    init(image: CGImage) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize
        layer?.magnificationFilter = .linear
        border.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
        border.borderWidth = 2
        border.isHidden = true
        border.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(border)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        border.frame = bounds
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            panel?.toggleActualSize()
        } else {
            window?.performDrag(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if panel?.handleKey(event) != true { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.isKeyWindow == true, event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        return panel?.handleKey(event) ?? false
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        panel?.contextMenu()
    }
}

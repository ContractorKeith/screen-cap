import AppKit

/// What a drag out of the thumbnail carries: a real file (Finder, Mail, Slack, browser uploads)
/// plus PNG data for apps that only take image data.
struct QuickAccessDragContents {
    var fileURL: URL?
    var pngData: Data?
}

/// The capture image. Shows the toolbar on hover, starts drags, and reports two-finger swipes.
final class QuickAccessThumbnailView: NSView, NSDraggingSource {
    var onHover: ((Bool) -> Void)?
    var onDoubleClick: (() -> Void)?
    /// Finger travel so far in the current swipe, for the panel to follow.
    var onSwipeChanged: ((CGFloat) -> Void)?
    var onSwipeEnded: ((SwipeTracker) -> Void)?
    /// The system cancelled the swipe: put the panel back, commit nothing.
    var onSwipeCancelled: (() -> Void)?
    var dragContents: (() -> QuickAccessDragContents)?
    let toolbar = QuickAccessToolbarView()

    private let image: CGImage
    private var mouseDownPoint: NSPoint?
    private var isHovered = false
    /// Keyboard focus (#129): a focus ring and the toolbar stay up while the panel is key.
    var isFocused = false {
        didSet {
            layer?.borderWidth = isFocused ? 3 : 1
            layer?.borderColor = isFocused ? NSColor.keyboardFocusIndicatorColor.cgColor
                                           : NSColor.white.withAlphaComponent(0.3).cgColor
            updateToolbar()
        }
    }
    private var gesture = SwipeGesture()

    init(image: CGImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resizeAspect
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor

        toolbar.frame = bounds
        toolbar.autoresizingMask = [.width, .height]
        toolbar.alphaValue = 0
        addSubview(toolbar)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ hovered: Bool) {
        isHovered = hovered
        updateToolbar()
        onHover?(hovered)
    }

    private func updateToolbar() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            toolbar.animator().alphaValue = isHovered || isFocused ? 1 : 0
        }
    }

    // MARK: - Click and drag

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        if event.clickCount == 2 { onDoubleClick?() }
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownPoint = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let point = event.locationInWindow
        guard hypot(point.x - start.x, point.y - start.y) > 4 else { return }
        mouseDownPoint = nil
        beginDrag(with: event)
    }

    private func beginDrag(with event: NSEvent) {
        let contents = dragContents?() ?? QuickAccessDragContents()
        let item = NSPasteboardItem()
        if let url = contents.fileURL { item.setString(url.absoluteString, forType: .fileURL) }
        if let png = contents.pngData { item.setData(png, forType: .png) }
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        dragItem.setDraggingFrame(bounds, contents: NSImage(cgImage: image, size: bounds.size))
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    // MARK: - Swipe

    override func scrollWheel(with event: NSEvent) {
        let inverted = event.isDirectionInvertedFromDevice
        let steps = gesture.handle(
            phase: SwipeGesture.Phase(event.phase), isMomentum: !event.momentumPhase.isEmpty,
            dx: SwipeClassifier.fingerDelta(event.scrollingDeltaX, invertedFromDevice: inverted),
            dy: SwipeClassifier.fingerDelta(event.scrollingDeltaY, invertedFromDevice: inverted)
        )
        for step in steps {
            switch step {
            case .moved(let dx): onSwipeChanged?(dx)
            case .ended(let tracker): onSwipeEnded?(tracker)
            case .cancelled: onSwipeCancelled?()
            }
        }
    }
}

extension SwipeGesture.Phase {
    init(_ phase: NSEvent.Phase) {
        self = []
        if phase.contains(.began) { insert(.began) }
        if phase.contains(.changed) { insert(.changed) }
        if phase.contains(.ended) { insert(.ended) }
        if phase.contains(.cancelled) { insert(.cancelled) }
        if phase.contains(.mayBegin) { insert(.mayBegin) }
    }
}

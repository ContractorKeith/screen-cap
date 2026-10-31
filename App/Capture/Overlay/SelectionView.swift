import AppKit
import ScreenCapKit

/// Draws the overlay for one display and forwards input to the shared `SelectionOverlay`.
///
/// Local coordinates equal global AppKit points minus the display origin, since the panel
/// exactly covers its display.
final class SelectionView: NSView {
    let display: DisplayInfo
    private unowned let overlay: SelectionOverlay

    init(display: DisplayInfo, overlay: SelectionOverlay) {
        self.display = display
        self.overlay = overlay
        super.init(frame: CGRect(origin: .zero, size: display.frame.size))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func localRect(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
    }

    func localPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - display.frame.minX, y: point.y - display.frame.minY)
    }

    // MARK: - Input

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    private func globalPoint(_ event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }

    override func mouseMoved(with event: NSEvent) { overlay.mouseMoved(to: globalPoint(event)) }
    override func mouseDown(with event: NSEvent) { overlay.mouseDown(at: globalPoint(event)) }
    override func mouseUp(with event: NSEvent) { overlay.mouseUp(at: globalPoint(event)) }

    override func mouseDragged(with event: NSEvent) {
        overlay.mouseDragged(to: globalPoint(event), shift: event.modifierFlags.contains(.shift))
    }

    override func flagsChanged(with event: NSEvent) {
        overlay.modifiersChanged(shift: event.modifierFlags.contains(.shift))
    }

    override func keyDown(with event: NSEvent) {
        if !overlay.handleKey(event) { super.keyDown(with: event) }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let state = overlay.state
        let hole: CGRect? = switch state.mode {
        case .area: state.rect.map(localRect)
        case .window: state.hoveredWindow.map { localRect($0.frame) }
        }
        drawDim(context, hole: hole)

        let mouseHere = display.frame.contains(state.mouse)
        switch state.mode {
        case .window:
            if let hole, let window = state.hoveredWindow { drawWindowHighlight(context, rect: hole, window: window) }
        case .area:
            drawArea(context, state: state, hole: hole, mouseHere: mouseHere)
        }
        if mouseHere, state.rect == nil, !state.isDragging { drawHint(state.mode) }
    }

    private func drawArea(_ context: CGContext, state: SelectionState, hole: CGRect?, mouseHere: Bool) {
        if let hole {
            drawSelection(context, rect: hole)
        } else if let previous = state.previousRect.map(localRect) {
            drawPreviousHint(context, rect: previous)
        }
        guard mouseHere, !state.toolbarVisible else { return }
        if state.fixedSize == nil, overlay.options.showsCrosshair {
            drawCrosshair(context, at: localPoint(state.mouse))
        }
        if overlay.options.showsMagnifier {
            Magnifier.draw(in: bounds, global: state.mouse, still: overlay.magnifierImage(for: display),
                           display: display, selection: state.rect?.size)
        }
    }

    private func drawDim(_ context: CGContext, hole: CGRect?) {
        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(overlay.options.showsStill ? 0.35 : 0.2).cgColor)
        context.addRect(bounds)
        if let hole { context.addRect(hole) }
        context.fillPath(using: .evenOdd)
        context.restoreGState()
    }

    private func drawSelection(_ context: CGContext, rect: CGRect) {
        context.saveGState()
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1)
        context.stroke(rect.insetBy(dx: -0.5, dy: -0.5))
        context.restoreGState()
        let label = SelectionMath.sizeLabel(rect.size)
        let below = CGPoint(x: rect.minX, y: rect.minY - 24)
        let anchor = below.y >= 4 ? below : CGPoint(x: rect.minX + 4, y: rect.minY + 4)
        OverlayBadge.draw(label, at: anchor, in: bounds)
    }

    private func drawPreviousHint(_ context: CGContext, rect: CGRect) {
        context.saveGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.stroke(rect)
        context.restoreGState()
    }

    private func drawWindowHighlight(_ context: CGContext, rect: CGRect, window: ShareableWindow) {
        context.saveGState()
        context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor)
        context.fill(rect)
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(3)
        context.stroke(rect.insetBy(dx: 1.5, dy: 1.5))
        context.restoreGState()
        let name = [window.appName, window.title]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " — ")
        let label = name.isEmpty ? SelectionMath.sizeLabel(rect.size) : "\(name)  \(SelectionMath.sizeLabel(rect.size))"
        OverlayBadge.draw(label, at: CGPoint(x: rect.midX - 60, y: rect.midY), in: bounds)
    }

    private func drawCrosshair(_ context: CGContext, at point: CGPoint) {
        context.saveGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
        context.setLineWidth(1)
        let x = point.x.rounded(.down) + 0.5, y = point.y.rounded(.down) + 0.5
        context.strokeLineSegments(between: [
            CGPoint(x: 0, y: y), CGPoint(x: bounds.maxX, y: y),
            CGPoint(x: x, y: 0), CGPoint(x: x, y: bounds.maxY)
        ])
        context.restoreGState()
    }

    private func drawHint(_ mode: SelectionMode) {
        let text = switch mode {
        case .area: "Drag to select · Space: window · ⌘K: size · ⇧: lock ratio · Return: previous · Esc: cancel"
        case .window: "Click a window · Space: area · Esc: cancel"
        }
        let size = OverlayBadge.size(of: text)
        OverlayBadge.draw(text, at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.maxY - 60), in: bounds)
    }
}

/// Small rounded label used for size badges and hints.
enum OverlayBadge {
    private static let padding = CGSize(width: 8, height: 4)

    private static var attributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white]
    }

    static func size(of text: String) -> CGSize {
        let textSize = (text as NSString).size(withAttributes: attributes)
        return CGSize(width: textSize.width + padding.width * 2, height: textSize.height + padding.height * 2)
    }

    /// Draws `text` with its bottom-left at `origin`, nudged inside `bounds`.
    static func draw(_ text: String, at origin: CGPoint, in bounds: CGRect) {
        let size = size(of: text)
        let rect = SelectionMath.clamp(CGRect(origin: origin, size: size), to: bounds.insetBy(dx: 4, dy: 4))
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: CGPoint(x: rect.minX + padding.width, y: rect.minY + padding.height),
                                withAttributes: attributes)
    }
}

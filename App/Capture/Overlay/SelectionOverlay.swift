import AppKit
import ScreenCapKit

/// Full-screen selection UI: one borderless panel per display above everything (PLAN §5.1).
///
/// Shows the frozen stills (or just a dim layer in live mode), tracks the drag or hovered
/// window, and returns a `SelectionOutcome`. It never captures; the coordinator does.
@MainActor
final class SelectionOverlay {
    let state: SelectionState
    let options: SelectionOptions
    let geometry: DisplayGeometry
    let picker: WindowPicker
    private let stills: [CapturedImage]
    private(set) var views: [SelectionView] = []
    private var panels: [OverlayPanel] = []
    private var continuation: CheckedContinuation<SelectionOutcome, Never>?
    var toolbar: AllInOneToolbar?
    var sizeField: FixedSizeField?

    init(stills: [CapturedImage], geometry: DisplayGeometry, windows: [ShareableWindow], options: SelectionOptions) {
        self.stills = stills
        self.geometry = geometry
        self.options = options
        self.picker = WindowPicker(windows: windows)
        self.state = SelectionState(mode: options.startMode, previousRect: options.previousRect)
    }

    /// Shows the overlay and waits for the user to finish or cancel.
    func run() async -> SelectionOutcome {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            show()
        }
    }

    private func show() {
        state.mouse = NSEvent.mouseLocation
        if state.mode == .window { state.hoveredWindow = picker.window(at: state.mouse) }
        for display in geometry.displays {
            let still = stills.first { $0.displayID == display.id }
            let panel = OverlayPanel(frame: display.frame)
            let view = SelectionView(display: display, still: still, overlay: self)
            panel.contentView = Self.container(for: view, still: options.showsStill ? still : nil, display: display)
            panel.orderFrontRegardless()
            panels.append(panel)
            views.append(view)
        }
        focusPanel(at: state.mouse)
        NSCursor.crosshair.push()
        let mode = String(describing: state.mode)
        appLog.notice("Selection overlay on \(self.panels.count) display(s), mode \(mode, privacy: .public)")
    }

    /// Image layer (the frozen still) under the transparent drawing view.
    private static func container(for view: SelectionView, still: CapturedImage?, display: DisplayInfo) -> NSView {
        let container = NSView(frame: CGRect(origin: .zero, size: display.frame.size))
        container.wantsLayer = true
        if let still {
            container.layer?.contents = OverlayImage.forDisplay(still.cgImage, display: display)
            container.layer?.contentsGravity = .resize
        }
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        return container
    }

    /// Makes the panel under `point` key so it gets keyboard input.
    func focusPanel(at point: CGPoint) {
        guard let index = geometry.displays.firstIndex(where: { $0.frame.contains(point) }) ?? views.indices.first,
              index < panels.count else { return }
        panels[index].makeKeyAndOrderFront(nil)
        panels[index].makeFirstResponder(views[index])
    }

    /// The view for the display holding most of `rect` (or the cursor).
    func view(for rect: CGRect?) -> SelectionView? {
        let display = rect.flatMap { geometry.display(bestFor: $0) } ?? geometry.display(containing: state.mouse)
        return views.first { $0.display.id == display?.id } ?? views.first
    }

    func redraw() {
        views.forEach { $0.needsDisplay = true }
    }

    /// Closes every panel and resumes `run()`.
    func finish(_ outcome: SelectionOutcome) {
        guard let continuation else { return }
        self.continuation = nil
        NSCursor.pop()
        toolbar?.removeFromSuperview()
        sizeField?.removeFromSuperview()
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        views.removeAll()
        continuation.resume(returning: outcome)
    }
}

/// Borderless, non-activating panel covering one display above everything, menu bar included.
final class OverlayPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Prepares a still for display, downsampling only when it is larger than the panel needs.
enum OverlayImage {
    /// Largest texture edge we hand to Core Animation.
    static let maxEdge = 8192

    static func forDisplay(_ image: CGImage, display: DisplayInfo) -> CGImage {
        let needed = display.pixelSize
        let limit = CGFloat(maxEdge)
        let scale = min(1, needed.width / CGFloat(image.width), limit / CGFloat(max(image.width, image.height)))
        guard scale < 1 else { return image }
        let width = max(Int(CGFloat(image.width) * scale), 1)
        let height = max(Int(CGFloat(image.height) * scale), 1)
        guard let space = image.colorSpace,
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return image }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}

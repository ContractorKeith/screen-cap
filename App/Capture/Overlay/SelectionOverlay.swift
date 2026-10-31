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
    /// The display arrangement; rebuilt when the displays change under the overlay (#131).
    private(set) var geometry: DisplayGeometry
    let picker: WindowPicker
    /// Frozen stills; emptied (live mode) if a display change leaves them stale (#131).
    private(set) var stills: [CapturedImage]
    private let sampler: PixelSampler?
    /// Latest live region under the pointer when the magnifier samples live (#90).
    private(set) var liveSample: CapturedImage?
    private var sampleThrottle = LiveSampleThrottle()
    private var sampleTimer: Timer?
    private var finished = false
    private(set) var views: [SelectionView] = []
    private var panels: [OverlayPanel] = []
    private var continuation: CheckedContinuation<SelectionOutcome, Never>?
    private var displayObserver: NSObjectProtocol?
    var toolbar: AllInOneToolbar?
    var sizeField: FixedSizeField?

    init(stills: [CapturedImage], geometry: DisplayGeometry, windows: [ShareableWindow], options: SelectionOptions,
         sampler: PixelSampler? = nil) {
        self.stills = stills
        self.sampler = sampler
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
        layOutPanels()
        NSCursor.crosshair.push()
        startLiveSampling()
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.displaysChanged(to: DisplayGeometry.fromCurrentScreens()) }
        }
        let mode = String(describing: state.mode)
        appLog.notice("Selection overlay on \(self.panels.count) display(s), mode \(mode, privacy: .public)")
    }

    /// One panel per display of `geometry`, showing its still if frozen.
    private func layOutPanels() {
        for display in geometry.displays {
            let still = stills.first { $0.displayID == display.id }
            let panel = OverlayPanel(frame: display.frame)
            let view = SelectionView(display: display, overlay: self)
            panel.contentView = Self.container(for: view, still: options.showsStill ? still : nil, display: display)
            panel.orderFrontRegardless()
            panels.append(panel)
            views.append(view)
        }
        focusPanel(at: state.mouse)
    }

    /// The displays changed while selecting (#131): rebuild the panels on the new arrangement so
    /// every display is covered and nothing selectable is off-screen. Stills that no longer match
    /// their display are dropped (live mode from here on); a selection that's now off-screen is cleared.
    func displaysChanged(to newGeometry: DisplayGeometry) {
        guard !finished, newGeometry != geometry, !newGeometry.displays.isEmpty else { return }
        let refresh = OverlayDisplayRefresh.make(stills: stills, rect: state.rect, previousRect: state.previousRect,
                                                 geometry: newGeometry)
        let frozeBefore = !stills.isEmpty
        geometry = refresh.geometry
        stills = refresh.stills
        liveSample = nil
        // Toolbar and size field live in the old panels' views; they go with them.
        let toolbarWasVisible = state.toolbarVisible
        hideToolbar()
        sizeField?.removeFromSuperview()
        sizeField = nil
        if refresh.rect != state.rect {
            state.rect = nil
            state.dragStart = nil
            state.fixedSize = nil
        }
        state.previousRect = refresh.previousRect
        if state.lastSelection.map({ OverlayDisplayRefresh.make(stills: [], rect: $0, previousRect: nil,
                                                                 geometry: newGeometry).rect == nil }) == true {
            state.lastSelection = nil
        }
        state.mouse = NSEvent.mouseLocation
        if state.mode == .window { state.hoveredWindow = picker.window(at: state.mouse) }
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        views.removeAll()
        layOutPanels()
        if toolbarWasVisible, let rect = state.rect { showToolbar(for: rect) }
        let summary = "\(geometry.displays.count) display(s), frozen \(frozeBefore) -> \(!stills.isEmpty)"
        appLog.notice("Selection overlay rebuilt after a display change: \(summary, privacy: .public)")
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

    /// Pixels the magnifier reads on `display`: its frozen still, or the live sample taken there.
    func magnifierImage(for display: DisplayInfo) -> CapturedImage? {
        switch options.magnifier {
        case .off: nil
        case .frozenStill: stills.first { $0.displayID == display.id }
        case .live: liveSample.flatMap { $0.displayID == display.id ? $0 : nil }
        }
    }

    // MARK: - Live magnifier sampling

    /// Refreshes on a timer too, so a still pointer over changing content stays current.
    private func startLiveSampling() {
        guard options.magnifier == .live, sampler != nil else { return }
        requestLiveSample()
        let timer = Timer(timeInterval: sampleThrottle.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.requestLiveSample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        sampleTimer = timer
    }

    /// Starts a small region grab under the pointer unless one is in flight or one started too recently.
    func requestLiveSample() {
        guard !finished, options.magnifier == .live, let sampler,
              state.mode == .area, !state.toolbarVisible,
              let display = geometry.display(containing: state.mouse),
              let rect = LiveSample.rect(around: state.mouse, in: display.frame),
              sampleThrottle.begin(now: ProcessInfo.processInfo.systemUptime) else { return }
        Task { [weak self] in
            let image = await sampler.sample(pointRect: rect, display: display)
            self?.acceptLiveSample(image)
        }
    }

    /// A finished live grab; nil (a failed grab) keeps the previous sample.
    func acceptLiveSample(_ image: CapturedImage?) {
        sampleThrottle.end()
        guard let image, !finished else { return }
        liveSample = image
        redraw()
    }

    func redraw() {
        views.forEach { $0.needsDisplay = true }
    }

    /// Closes every panel and resumes `run()`.
    func finish(_ outcome: SelectionOutcome) {
        guard let continuation else { return }
        self.continuation = nil
        finished = true
        displayObserver.map(NotificationCenter.default.removeObserver)
        displayObserver = nil
        sampleTimer?.invalidate()
        sampleTimer = nil
        liveSample = nil
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

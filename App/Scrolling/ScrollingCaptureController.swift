import AppKit
import ApplicationServices
import ScreenCapKit
import SwiftUI

/// Runs one scrolling capture over a selected region (PLAN §5.4): control and preview panels
/// beside the region, repeated stills stitched as they arrive, optional auto-scroll, then the
/// stitched image goes through the coordinator's normal after-capture path.
@MainActor
final class ScrollingCaptureController {
    private let coordinator: CaptureCoordinator
    private let settings: ScrollingSettings
    private let poster: any ScrollEventPosting
    private let launch: ScrollingLaunchOptions

    private var session = ScrollingSession()
    private let model = ScrollingPanelModel()
    private var panels: [NSPanel] = []
    private weak var controlPanel: NSPanel?
    private let previewView = ScrollingPreviewView()
    private var keyMonitors: [Any] = []
    private var wake: CheckedContinuation<Void, Never>?
    /// When the gap hint, if shown, goes away.
    private var hintUntil: ContinuousClock.Instant?
    /// `--region` or a URL with `start=true` starts the next capture without waiting for Start.
    private var startsImmediately = false
    /// Auto-scroll for the next capture from a URL (`autoscroll=`); nil uses the launch option or setting.
    private var autoScrollOverride: Bool?
    private var requestObserver: NSObjectProtocol?

    init(coordinator: CaptureCoordinator, settings: ScrollingSettings = .shared,
         poster: any ScrollEventPosting = SystemScrollEventPoster(),
         launch: ScrollingLaunchOptions = .parse(CommandLine.arguments)) {
        self.coordinator = coordinator
        self.settings = settings
        self.poster = poster
        self.launch = launch
    }

    /// Hooks into the coordinator's `.scrolling` flow. Called once from `installFeatures()`.
    @discardableResult
    static func install(on coordinator: CaptureCoordinator) -> ScrollingCaptureController {
        let controller = ScrollingCaptureController(coordinator: coordinator)
        coordinator.scrollingRegion = controller.launch.region
        controller.startsImmediately = controller.launch.region != nil
        coordinator.scrollingHandler = { [controller] rect, context, action in
            await controller.run(region: rect.integral, context: context, action: action)
        }
        controller.observeRegionRequests()
        return controller
    }

    // MARK: - Flow

    func run(region: CGRect, context: FilenameTemplate.Context, action: AfterCaptureAction?) async {
        let startsNow = startsImmediately
        let autoScroll = autoScrollOverride ?? launch.autoScroll ?? settings.autoScroll
        startsImmediately = false
        autoScrollOverride = nil
        session = ScrollingSession(autoScroll: autoScroll,
                                   axis: settings.horizontal ? .horizontal : .vertical)
        session.beginSelection()
        showUI(around: region)
        defer { hideUI() }
        syncModel()

        if startsNow { session.start() }
        while session.phase == .selecting { await waitForUser() }
        guard session.isCapturing else {
            appLog.info("Scrolling capture cancelled")
            return
        }
        let summary = "\(String(describing: session.mode)), \(session.axis.rawValue)"
        appLog.notice("Scrolling capture started: \(summary, privacy: .public)")
        let stitched = await captureFrames(region: region)
        guard session.phase == .finishing else {
            appLog.info("Scrolling capture cancelled")
            return
        }
        let reason = String(describing: session.stopReason)
        appLog.notice("Scrolling capture stopped: \(reason, privacy: .public)")
        session.delivered(hasImage: stitched != nil)
        hideUI()
        if let stitched {
            await coordinator.deliver(stitched, kind: .scrolling, context: context, action: action)
        }
    }

    /// Grabs stills on a timer until the session leaves `.capturing`; returns the stitched image.
    private func captureFrames(region: CGRect) async -> CapturedImage? {
        let geometry = DisplayGeometry.fromCurrentScreens()
        let quartz = geometry.quartzRect(fromAppKit: region)
        let scrollPoint = CGPoint(x: quartz.midX, y: quartz.midY)
        let axis = session.axis
        let regionLength = axis == .vertical ? region.height : region.width
        // Keep at least half the region overlapping between steps so frames always align.
        let step = max(10, min(settings.scrollStep, Int(regionLength / 2)))
        let interval = settings.frameInterval
        let scroller = AutoScroller(axis: axis, step: step, interval: interval, poster: poster)
        defer { scroller.cancel() }

        var stitcher: Stitcher?
        var lastFrame: CapturedImage?
        var lastPreview = ContinuousClock.now - .seconds(1)
        let clock = ContinuousClock()
        while session.isCapturing {
            let tick = clock.now
            syncScroller(scroller, at: scrollPoint)
            let frame: CapturedImage
            do {
                frame = try await coordinator.service.captureArea(pointRect: region)
            } catch {
                appLog.error("Scrolling frame failed: \(String(describing: error), privacy: .public)")
                session.stop()
                break
            }
            let active = stitcher ?? Stitcher(axis: axis, scale: frame.scale,
                                               maxLength: Int(CGFloat(settings.maxLength) * frame.scale))
            stitcher = active
            lastFrame = frame
            // While auto-scrolling, the posted step (points) tells the stitcher how far content moves.
            let expected = scroller.state == .scrolling ? Int((CGFloat(step) * frame.scale).rounded()) : nil
            await active.setExpectedStep(expected)
            let outcome = await active.append(frame: frame.cgImage)
            guard session.isCapturing else { break } // Cancel/Stop while appending
            session.record(outcome)
            lastPreview = await present(outcome, from: active, lastPreview: lastPreview)
            syncModel()
            try? await Task.sleep(until: tick + interval, clock: clock)
        }
        scroller.cancel()
        guard session.phase == .finishing, let stitcher, let lastFrame,
              let image = await stitcher.finish() else { return nil }
        let scale = lastFrame.scale
        let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let origin = CGPoint(x: region.minX, y: region.maxY - size.height)
        return CapturedImage(cgImage: image, scale: scale, pointRect: CGRect(origin: origin, size: size),
                             displayID: lastFrame.displayID)
    }

    /// Refreshes the preview after progress and shows the gap hint for a few seconds after a jump.
    private func present(_ outcome: Stitcher.AppendOutcome, from stitcher: Stitcher,
                         lastPreview: ContinuousClock.Instant) async -> ContinuousClock.Instant {
        let now = ContinuousClock.now
        if let until = hintUntil, now >= until {
            model.hint = nil
            hintUntil = nil
        }
        switch outcome {
        case .started, .appended, .maxLengthReached:
            return await refreshPreview(stitcher, last: lastPreview, force: !session.isCapturing)
        case .gapDetected:
            appLog.info("Scrolling capture: content jumped; gap marked")
            model.hint = ScrollingPanelModel.gapHint
            hintUntil = now + .seconds(4)
            return await refreshPreview(stitcher, last: lastPreview, force: true)
        case .noMovement, .unrelated:
            return lastPreview
        }
    }

    /// Composing copies the whole canvas, so refresh less often as the image grows.
    private func refreshPreview(_ stitcher: Stitcher, last: ContinuousClock.Instant, force: Bool) async
        -> ContinuousClock.Instant {
        let length = session.axis == .vertical ? model.capturedSize.height : model.capturedSize.width
        let spacing = Duration.milliseconds(200 + Int(length / 40))
        let now = ContinuousClock.now
        guard force || now - last >= spacing, let image = await stitcher.currentImage() else { return last }
        previewView.image = image
        model.capturedSize = CGSize(width: image.width, height: image.height)
        return now
    }

    /// Starts or stops auto-scroll to match the session mode; falls back to manual without Accessibility.
    private func syncScroller(_ scroller: AutoScroller, at point: CGPoint) {
        switch session.mode {
        case .auto where scroller.state != .scrolling:
            if scroller.start(at: point) == .needsAccessibility {
                session.accessibilityDenied()
                syncModel()
                showAccessibilitySheet()
            }
        case .manual where scroller.state == .scrolling:
            scroller.cancel()
        default:
            break
        }
    }

    // MARK: - User actions

    private func waitForUser() async {
        await withCheckedContinuation { wake = $0 }
    }

    private func poke() {
        syncModel()
        wake?.resume()
        wake = nil
    }

    private func bindModel() {
        model.onStart = { [weak self] in self?.session.start(); self?.poke() }
        model.onStop = { [weak self] in self?.session.stop(); self?.poke() }
        model.onCancel = { [weak self] in self?.session.cancel(); self?.poke() }
        model.onAutoScroll = { [weak self] in self?.session.setAutoScroll($0); self?.poke() }
        model.onHorizontal = { [weak self] in
            self?.session.setAxis($0 ? .horizontal : .vertical)
            self?.poke()
        }
    }

    private func syncModel() {
        model.phase = session.phase
        model.autoScroll = session.autoScroll
        model.horizontal = session.axis == .horizontal
    }

    private func showUI(around region: CGRect) {
        bindModel()
        let screen = NSScreen.screens.first { $0.frame.intersects(region) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? region
        let layout = ScrollingPanelLayout.frames(region: region, screen: screen)

        let border = ScrollingPanel(frame: region.insetBy(dx: -3, dy: -3), titled: false)
        border.contentView = RegionBorderView()

        let control = ScrollingPanel(frame: layout.control, titled: true)
        control.contentView = NSHostingView(rootView: ScrollingControlView(model: model))

        let preview = ScrollingPanel(frame: layout.preview, titled: true)
        preview.contentView = previewView
        previewView.image = nil
        model.hint = nil
        hintUntil = nil
        model.capturedSize = .zero

        panels = [border, preview, control]
        controlPanel = control
        panels.forEach { $0.orderFrontRegardless() }
        installEscapeMonitors()
    }

    private func hideUI() {
        keyMonitors.forEach(NSEvent.removeMonitor)
        keyMonitors = []
        panels.forEach { $0.orderOut(nil) }
        panels = []
    }

    /// Esc stops (and keeps) the capture. The global monitor sees keys sent to the scrolled app
    /// once Accessibility is granted; the local one covers our own panels.
    private func installEscapeMonitors() {
        let escape: UInt16 = 53
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == escape else { return event }
            MainActor.assumeIsolated {
                self?.session.escape()
                self?.poke()
            }
            return nil
        }) {
            keyMonitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == escape else { return }
            MainActor.assumeIsolated {
                self?.session.escape()
                self?.poke()
            }
        }) {
            keyMonitors.append(global)
        }
    }
}

// MARK: - URL scheme regions

extension ScrollingCaptureController {
    /// `screencap://scrolling-capture` with a region posts `.scrollingCaptureRequested`
    /// (`rect`, `start`, `autoscroll`); see docs/url-scheme.md.
    fileprivate func observeRegionRequests() {
        requestObserver = NotificationCenter.default.addObserver(
            forName: .scrollingCaptureRequested, object: nil, queue: .main
        ) { [weak self] note in
            guard let rect = (note.userInfo?[AutomationKey.rect] as? NSValue)?.rectValue else { return }
            let startNow = note.userInfo?[AutomationKey.start] as? Bool ?? false
            let autoScroll = note.userInfo?[AutomationKey.autoscroll] as? Bool
            MainActor.assumeIsolated {
                self?.start(region: rect, startNow: startNow, autoScroll: autoScroll)
            }
        }
    }

    /// Starts a scrolling capture of a pre-chosen region (global AppKit points), skipping selection.
    func start(region: CGRect, startNow: Bool, autoScroll: Bool?) {
        startsImmediately = startNow
        autoScrollOverride = autoScroll
        coordinator.scrollingRegion = region
        guard coordinator.capture(.scrolling) != nil else {
            // No permission or another capture is running: drop the request instead of leaking it
            // into the next interactive scrolling capture.
            appLog.notice("Scrolling capture request ignored: a capture is running or permission is missing")
            coordinator.scrollingRegion = nil
            startsImmediately = false
            autoScrollOverride = nil
            return
        }
    }
}

extension ScrollingSettings {
    /// One instance shared by the controller and the settings pane.
    static let shared = ScrollingSettings()
}

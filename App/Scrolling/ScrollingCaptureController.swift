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
    private let frameSource: any ScrollingFrameSource
    private let settings: ScrollingSettings
    private let poster: any ScrollEventPosting
    private let launch: ScrollingLaunchOptions

    private var session = ScrollingSession()
    private let model = ScrollingPanelModel()
    private var panels: [NSPanel] = []
    weak var controlPanel: NSPanel?
    private let previewView = ScrollingPreviewView()
    private var keyMonitors: [Any] = []
    private var wake: CheckedContinuation<Void, Never>?
    /// When the gap hint, if shown, goes away.
    private var hintUntil: ContinuousClock.Instant?
    /// The last held frame was ambiguous (repeating rows) rather than a jump; picks the hint.
    private var heldBecauseRepeating = false
    /// `--region` or a URL with `start=true` starts the next capture without waiting for Start.
    private var startsImmediately = false
    /// Auto-scroll for the next capture from a URL (`autoscroll=`); nil uses the launch option or setting.
    private var autoScrollOverride: Bool?
    private var requestObserver: NSObjectProtocol?

    init(coordinator: CaptureCoordinator, settings: ScrollingSettings = .shared,
         poster: any ScrollEventPosting = SystemScrollEventPoster(),
         launch: ScrollingLaunchOptions = .parse(CommandLine.arguments),
         frameSource: (any ScrollingFrameSource)? = nil) {
        self.coordinator = coordinator
        self.frameSource = frameSource ?? coordinator.service
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
        let end = await captureFrames(region: region)
        guard session.phase == .finishing else {
            appLog.info("Scrolling capture cancelled")
            return
        }
        let reason = String(describing: session.stopReason)
        appLog.notice("Scrolling capture stopped: \(reason, privacy: .public)")
        hideUI()
        await conclude(end, context: context, action: action)
    }

    /// Grabs stills on a timer until the session leaves `.capturing`; returns how it ended,
    /// or nil if there is nothing to deliver or report.
    private func captureFrames(region: CGRect) async -> ScrollingCaptureEnd? {
        let geometry = DisplayGeometry.fromCurrentScreens()
        let quartz = geometry.quartzRect(fromAppKit: region)
        let scrollPoint = CGPoint(x: quartz.midX, y: quartz.midY)
        let axis = session.axis
        let regionLength = axis == .vertical ? region.height : region.width
        // Keep at least half the region overlapping between steps so frames always align.
        let step = max(10, min(settings.scrollStep, Int(regionLength / 2)))
        let interval = settings.frameInterval
        let scroller = AutoScroller(axis: axis, step: step, poster: poster)
        defer { scroller.cancel() }

        let collector = ScrollingFrameCollector(source: frameSource, region: region, axis: axis,
                                                maxLength: settings.maxLength)
        // Capture first, then scroll (#98); the probe waits at least 100 ms for the page to redraw.
        let loop = ScrollingFrameLoop(collector: collector, scroller: scroller,
                                      settle: max(interval, .milliseconds(100)))
        var lastPreview = ContinuousClock.now - .seconds(1)
        let clock = ContinuousClock()
        while session.isCapturing {
            let tick = clock.now
            syncScroller(scroller, at: scrollPoint) // arms auto-scroll; posts nothing yet
            let frame = await loop.next { [self] frame in
                // Cancel/Stop while appending ends the loop without recording.
                guard session.isCapturing else { return false }
                session.record(frame.outcome, frameChanged: frame.changed)
                return session.isCapturing
            }
            guard let frame else {
                let detail = collector.failure.map { String(describing: $0) } ?? "unknown"
                appLog.error("Scrolling frame failed: \(detail, privacy: .public)")
                session.fail()
                break
            }
            let outcome = String(describing: frame.outcome)
            appLog.debug("Scrolling frame: \(outcome, privacy: .public), changed \(frame.changed)")
            if let stitcher = collector.stitcher {
                lastPreview = await present(frame.outcome, from: stitcher, lastPreview: lastPreview)
            }
            syncModel()
            try? await Task.sleep(until: tick + interval, clock: clock)
        }
        scroller.cancel()
        guard session.phase == .finishing else { return nil }
        return await collector.finish()
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
            showHint(heldBecauseRepeating ? ScrollingPanelModel.repeatHint : ScrollingPanelModel.gapHint, now: now)
            return await refreshPreview(stitcher, last: lastPreview, force: true)
        case .unrelated, .ambiguous:
            // A held frame is kept after a seam if the user stops now, so warn straight away.
            heldBecauseRepeating = outcome == .ambiguous
            showHint(heldBecauseRepeating ? ScrollingPanelModel.repeatHint : ScrollingPanelModel.heldHint, now: now)
            return lastPreview
        case .noMovement:
            return lastPreview
        }
    }

    private func showHint(_ hint: String, now: ContinuousClock.Instant) {
        model.hint = hint
        hintUntil = now + .seconds(4)
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
        heldBecauseRepeating = false
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

// MARK: - Ending

extension ScrollingCaptureController {
    /// Delivers what was stitched, if anything, and names any problem in a HUD (#71, #76).
    fileprivate func conclude(_ end: ScrollingCaptureEnd?, context: FilenameTemplate.Context,
                              action: AfterCaptureAction?) async {
        switch end {
        case nil:
            session.delivered(hasImage: false)
        case let .failed(problem):
            session.delivered(hasImage: false)
            appLog.error("Scrolling capture failed: \(problem, privacy: .public)")
            coordinator.record(.failed(problem))
            CaptureHUD.show("Scrolling capture failed", detail: problem)
        case let .image(image, problem, gapMarked):
            session.delivered(hasImage: true)
            await coordinator.deliver(image, kind: .scrolling, context: context, action: action)
            if let problem {
                appLog.error("Scrolling capture stopped early: \(problem, privacy: .public)")
                coordinator.record(.failed(problem))
                CaptureHUD.show("Scrolling capture stopped early",
                                detail: "\(problem) What was stitched so far was kept.")
            } else if gapMarked {
                CaptureHUD.show("Gap marked in the capture",
                                detail: "Some screens didn't line up (repeating rows or a fast scroll); "
                                    + "a dashed line marks each gap.")
            }
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

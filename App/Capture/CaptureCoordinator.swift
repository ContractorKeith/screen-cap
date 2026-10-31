import AppKit
import ScreenCapKit

/// Owns the capture flow: permission check, overlays, the capture itself, then the
/// after-capture action and the history write.
///
/// Shortcuts, menu items, `--capture` and the URL scheme all call `capture(_:action:)`;
/// URL regions use `capture(_:rect:action:)`.
@MainActor
final class CaptureCoordinator {
    /// Receives `.overlay`, `.annotate` and `.pin` results. Quick Access replaces the default.
    var sink: CaptureSink
    let output: CaptureOutput
    let settings: AppSettings
    /// Handed to features that grab the screen themselves (text, scrolling).
    let service: CaptureService
    /// What the flows here capture with; `service` unless a test passes a fake.
    let source: any CaptureSource
    let previousArea: PreviousArea
    let selfTimer = SelfTimer()
    /// Covers desktop icons during captures when "Hide desktop icons while capturing" is on.
    var desktopIcons: DesktopIconsController?
    /// Runs scrolling capture over a selected region (App/Scrolling); it delivers through `deliver`.
    /// Nil posts `.scrollingCaptureRequested` instead.
    var scrollingHandler: (@MainActor (CGRect, FilenameTemplate.Context, AfterCaptureAction?) async -> Void)?
    /// Region for the next scrolling capture, skipping the selection overlay (`--region`). Used once.
    var scrollingRegion: CGRect?
    /// Runs OCR on a selected area's image (App/TextRecognition) and returns the text for History.
    /// Awaited, so `--quit` waits for it. The coordinator writes the `.text` History record itself
    /// (#53, #72), so no handler can skip it. Nil posts `.captureTextRequested` with the rect instead.
    var textHandler: (@MainActor (CGImage) async throws -> String?)?
    /// Whether `.overlay` shows Quick Access; when off the coordinator saves instead (#75).
    var showsQuickAccess: @MainActor () -> Bool = { QuickAccessPreferences.showAfterCapture }
    /// Busy and save/copy failure HUDs; tests swap these out.
    var alerts = CaptureAlerts()
    /// URL-scheme captures waiting for the running one to finish, oldest first (#79).
    private var pending: [Pending] = []
    /// Most URL captures held while another runs; more get the busy HUD.
    static let queueLimit = 5
    let frontApps = FrontAppTracker()
    /// How the most recent capture request ended; set when it finishes or is refused.
    private(set) var lastOutcome: CaptureOutcome?
    /// Outcome of the capture running now, folded as images are delivered.
    private var runningOutcome = CaptureOutcome.cancelled
    /// Shared with features that update records (Quick Access close/restore/delete).
    let history: HistoryStore?
    private let hasPermission: () -> Bool
    private let showOnboarding: () -> Void
    private var current: Task<Void, Never>?

    /// Pause between hiding an overlay and a live capture, so the window server has redrawn.
    static let overlayHideDelay = Duration.milliseconds(150)

    init(
        settings: AppSettings,
        service: CaptureService = CaptureService(),
        source: (any CaptureSource)? = nil,
        history: HistoryStore?,
        hasPermission: @escaping () -> Bool = { ScreenRecordingPermission.isGranted },
        showOnboarding: @escaping () -> Void
    ) {
        self.settings = settings
        self.service = service
        self.source = source ?? service
        self.history = history
        self.hasPermission = hasPermission
        self.showOnboarding = showOnboarding
        self.previousArea = PreviousArea(store: SettingsPreviousAreaStore(settings: settings))
        self.output = CaptureOutput(settings: settings)
        self.sink = SavingCaptureSink(output: output)
    }

    var isCapturing: Bool { current != nil }
    /// No capture running and none queued.
    var isIdle: Bool { current == nil && pending.isEmpty }
    var queuedCount: Int { pending.count }

    /// Starts a capture. `action` overrides the per-shortcut after-capture setting.
    /// `queueIfBusy` (URL scheme) waits for a running capture instead of being refused.
    ///
    /// Returns the running task (await it to know when the capture is fully delivered),
    /// or nil if permission is missing, the request was queued, or another capture is in progress.
    @discardableResult
    func capture(_ kind: CaptureKind, action: AfterCaptureAction? = nil,
                 queueIfBusy: Bool = false) -> Task<Void, Never>? {
        let app = frontApps.app
        return start(kind.rawValue, queueIfBusy: queueIfBusy) { coordinator in
            try await coordinator.run(kind, action: action, app: app)
        }
    }

    /// Captures a known rect in global AppKit points without the selection overlay
    /// (All-In-One opens with the rect pre-selected).
    @discardableResult
    func capture(_ kind: CaptureKind, rect: CGRect, action: AfterCaptureAction? = nil,
                 queueIfBusy: Bool = false) -> Task<Void, Never>? {
        let app = frontApps.app
        return start("\(kind.rawValue) at \(rect)", queueIfBusy: queueIfBusy) { coordinator in
            try await coordinator.run(kind, rect: rect, action: action, app: app)
        }
    }

    /// Captures an app's frontmost window without the picker. Used by `--capture window --window <app>`.
    @discardableResult
    func captureWindow(ofApp app: String, action: AfterCaptureAction? = nil) -> Task<Void, Never>? {
        let front = frontApps.app
        return start("window of \(app)") { coordinator in
            try await coordinator.runWindow(ofApp: app, action: action, front: front)
        }
    }

    private struct Pending {
        let label: String
        let body: @MainActor (CaptureCoordinator) async throws -> Void
    }

    /// Permission check, one capture at a time (URL captures queue), error logging and the failure HUD.
    private func start(_ label: String, queueIfBusy: Bool = false,
                       _ body: @escaping @MainActor (CaptureCoordinator) async throws -> Void)
        -> Task<Void, Never>? {
        guard hasPermission() else {
            appLog.notice("Screen Recording not granted; showing onboarding")
            lastOutcome = .notStarted("Screen Recording permission not granted")
            showOnboarding()
            return nil
        }
        guard current == nil else {
            if queueIfBusy, pending.count < Self.queueLimit {
                pending.append(Pending(label: label, body: body))
                appLog.notice("Capture \(label, privacy: .public) queued behind the running capture")
                return nil
            }
            appLog.notice("Capture \(label, privacy: .public) ignored: another capture is in progress")
            alerts.busy()
            return nil
        }
        runningOutcome = .cancelled
        let task = Task { [weak self] in
            guard let self else { return }
            let coverIcons = settings.hideDesktopIcons && desktopIcons?.beginTemporaryHide() == true
            do {
                // Let the window server draw the covers before the first still is taken.
                if coverIcons { try await Task.sleep(for: Self.overlayHideDelay) }
                try await body(self)
            } catch {
                let detail = String(describing: error)
                appLog.error("Capture \(label, privacy: .public) failed: \(detail, privacy: .public)")
                record(.failed(error.localizedDescription))
                CaptureFailureHUD.showCaptureFailed(error)
            }
            if coverIcons { desktopIcons?.endTemporaryHide() }
            lastOutcome = runningOutcome
            self.current = nil
            startNextPending()
        }
        current = task
        return task
    }

    /// Runs queued URL captures in arrival order once nothing else is running.
    private func startNextPending() {
        while current == nil, !pending.isEmpty {
            let next = pending.removeFirst()
            _ = start(next.label, next.body)
        }
    }

    /// Folds an event into the running capture's outcome.
    func record(_ outcome: CaptureOutcome) {
        runningOutcome = runningOutcome.merged(with: outcome)
    }

    /// Self-timer with a specific length; remembers it as the new default.
    @discardableResult
    func startSelfTimer(seconds: Int, action: AfterCaptureAction? = nil) -> Task<Void, Never>? {
        settings.selfTimerSeconds = seconds
        return capture(.selfTimer, action: action)
    }

    // MARK: - Delivery

    /// Records in history at full resolution, then applies the after-capture action.
    /// The output scale is applied by `CaptureOutput` when a file or the clipboard is written.
    func deliver(_ image: CapturedImage, kind: CaptureKind, context: FilenameTemplate.Context,
                 action: AfterCaptureAction?) async {
        var context = context
        context.kind = kind.filenameKind
        var result = CaptureResult(image: image, kind: kind, context: context)
        let record = await addToHistory(result)
        result.historyRecordID = record?.id
        result.historyFileURL = record?.fileURL
        var action = action ?? settings.afterCaptureAction(for: kind.shortcut)
        // Quick Access off: save here, so a failure gets the HUD and a failed outcome (#75).
        if action == .overlay, !showsQuickAccess() { action = .save }
        let size = "\(image.cgImage.width)x\(image.cgImage.height)"
        let summary = "\(kind.rawValue) \(size) px, \(action.rawValue)"
        appLog.notice("Captured \(summary, privacy: .public)")
        do {
            switch action {
            case .save:
                let url = try await output.save(result)
                appLog.notice("Saved \(url.path, privacy: .public)")
            case .copy:
                try await output.copy(result)
                appLog.notice("Copied to the pasteboard")
            case .overlay, .annotate, .pin:
                await sink.deliver(result, action: action)
            }
            self.record(.delivered)
        } catch {
            let reason = error.localizedDescription
            appLog.error("After-capture \(action.rawValue, privacy: .public) failed: \(reason, privacy: .public)")
            self.record(.failed(reason))
            alerts.outputFailed(action, error, result, output)
        }
    }

    private func addToHistory(_ result: CaptureResult) async -> CaptureRecord? {
        guard let history else { return nil }
        let metadata = CaptureMetadata(scale: Double(result.image.scale), appName: result.context.app,
                                       windowTitle: result.context.window)
        do {
            // FilenameTemplate.Kind raw values match the history kinds (area, window, fullscreen, scrolling).
            return try await history.add(image: result.image.cgImage,
                                         kind: .init(rawValue: result.kind.filenameKind.rawValue),
                                         metadata: metadata)
        } catch {
            appLog.error("History write failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Front app name and its frontmost window title, for `{app}` and `{window}`.
    /// `app` is taken when the request arrived, so a queued or URL capture names the right app.
    func frontContext(windows: [ShareableWindow], app: FrontApp?) -> FilenameTemplate.Context {
        let title = windows.first { $0.processID == app?.processID && $0.layer == 0 }?.title
        return FilenameTemplate.Context(app: app?.name, window: title)
    }
}

/// The HUDs the coordinator shows; replaceable so tests run without panels.
@MainActor
struct CaptureAlerts {
    var busy: @MainActor () -> Void = { CaptureFailureHUD.showBusy() }
    var outputFailed: @MainActor (AfterCaptureAction, Error, CaptureResult, CaptureOutput) -> Void = {
        CaptureFailureHUD.showOutputFailed($0, error: $1, result: $2, output: $3)
    }
}

/// Persists "previous area" in settings so it survives relaunch.
@MainActor
final class SettingsPreviousAreaStore: PreviousAreaStore {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    var lastRect: CGRect? {
        get { settings.lastCaptureRect }
        set { settings.lastCaptureRect = newValue }
    }
}

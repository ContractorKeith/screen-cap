import AppKit
import ScreenCapKit

/// Owns the capture flow: permission check, overlays, the capture itself, then the
/// after-capture action and the history write.
///
/// Shortcuts, menu items, `--capture` and (later) the URL scheme all call `capture(_:action:)`.
@MainActor
final class CaptureCoordinator {
    /// Receives `.overlay`, `.annotate` and `.pin` results. Quick Access replaces the default.
    var sink: CaptureSink
    let output: CaptureOutput
    let settings: AppSettings
    let service: CaptureService
    let previousArea: PreviousArea
    let selfTimer = SelfTimer()
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
        history: HistoryStore?,
        hasPermission: @escaping () -> Bool = { ScreenRecordingPermission.isGranted },
        showOnboarding: @escaping () -> Void
    ) {
        self.settings = settings
        self.service = service
        self.history = history
        self.hasPermission = hasPermission
        self.showOnboarding = showOnboarding
        self.previousArea = PreviousArea(store: SettingsPreviousAreaStore(settings: settings))
        self.output = CaptureOutput(settings: settings)
        self.sink = SavingCaptureSink(output: output)
    }

    var isCapturing: Bool { current != nil }

    /// Starts a capture. `action` overrides the per-shortcut after-capture setting.
    ///
    /// Returns the running task (await it to know when the capture is fully delivered),
    /// or nil if permission is missing or another capture is in progress.
    @discardableResult
    func capture(_ kind: CaptureKind, action: AfterCaptureAction? = nil) -> Task<Void, Never>? {
        start(kind.rawValue) { coordinator in try await coordinator.run(kind, action: action) }
    }

    /// Captures an app's frontmost window without the picker. Used by `--capture window --window <app>`.
    @discardableResult
    func captureWindow(ofApp app: String, action: AfterCaptureAction? = nil) -> Task<Void, Never>? {
        start("window of \(app)") { coordinator in try await coordinator.runWindow(ofApp: app, action: action) }
    }

    /// Permission check, one capture at a time, error logging.
    private func start(_ label: String, _ body: @escaping @MainActor (CaptureCoordinator) async throws -> Void)
        -> Task<Void, Never>? {
        guard hasPermission() else {
            appLog.notice("Screen Recording not granted; showing onboarding")
            showOnboarding()
            return nil
        }
        guard current == nil else { return nil }
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await body(self)
            } catch {
                let reason = String(describing: error)
                appLog.error("Capture \(label, privacy: .public) failed: \(reason, privacy: .public)")
            }
            self.current = nil
        }
        current = task
        return task
    }

    /// Self-timer with a specific length; remembers it as the new default.
    @discardableResult
    func startSelfTimer(seconds: Int, action: AfterCaptureAction? = nil) -> Task<Void, Never>? {
        settings.selfTimerSeconds = seconds
        return capture(.selfTimer, action: action)
    }

    // MARK: - Delivery

    /// Scales, records in history, then applies the after-capture action.
    func deliver(_ image: CapturedImage, kind: CaptureKind, context: FilenameTemplate.Context,
                 action: AfterCaptureAction?) async {
        var context = context
        context.kind = kind.filenameKind
        var result = CaptureResult(image: OutputScaler.scaled(image, to: settings.retinaScale),
                                   kind: kind, context: context)
        result.historyRecordID = await addToHistory(result)
        let action = action ?? settings.afterCaptureAction(for: kind.shortcut)
        let size = "\(result.image.cgImage.width)x\(result.image.cgImage.height)"
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
        } catch {
            let reason = error.localizedDescription
            appLog.error("After-capture \(action.rawValue, privacy: .public) failed: \(reason, privacy: .public)")
        }
    }

    private func addToHistory(_ result: CaptureResult) async -> UUID? {
        guard let history else { return nil }
        let metadata = CaptureMetadata(scale: Double(result.image.scale), appName: result.context.app,
                                       windowTitle: result.context.window)
        do {
            // FilenameTemplate.Kind raw values match the history kinds (area, window, fullscreen, scrolling).
            return try await history.add(image: result.image.cgImage,
                                         kind: .init(rawValue: result.kind.filenameKind.rawValue),
                                         metadata: metadata).id
        } catch {
            appLog.error("History write failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Front app name and its frontmost window title, for `{app}` and `{window}`.
    func frontContext(windows: [ShareableWindow]) -> FilenameTemplate.Context {
        let app = NSWorkspace.shared.frontmostApplication
        let title = windows.first { $0.processID == app?.processIdentifier && $0.layer == 0 }?.title
        return FilenameTemplate.Context(app: app?.localizedName, window: title)
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

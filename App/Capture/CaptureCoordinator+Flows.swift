import AppKit
import ScreenCapKit

// One flow per capture kind. Everything here runs on the main actor between awaits.
extension CaptureCoordinator {
    func run(_ kind: CaptureKind, action: AfterCaptureAction?, app: FrontApp?) async throws {
        let geometry = DisplayGeometry.fromCurrentScreens()
        let windows = (try? await source.shareableWindows()) ?? []
        let context = frontContext(windows: windows, app: app)
        let flow = Flow(kind: kind, geometry: geometry, context: context, action: action)
        switch kind {
        case .fullscreen:
            try await captureFullscreen(flow)
        case .previousArea:
            if let rect = previousArea.rect(validIn: geometry) {
                await deliver(try await source.captureArea(pointRect: rect), flow)
            } else {
                try await select(flow, windows: windows)
            }
        case .scrolling:
            if let rect = scrollingRegion {
                scrollingRegion = nil
                await scroll(rect, flow)
            } else {
                try await select(flow, windows: windows)
            }
        case .area, .window, .allInOne, .text, .selfTimer:
            // Self-timer: pick the area (or window) first, then count down, then capture live (PLAN §3.1).
            try await select(flow, windows: windows)
        }
    }

    /// A capture at a known rect (URL scheme regions), skipping interactive selection.
    func run(_ kind: CaptureKind, rect: CGRect, action: AfterCaptureAction?, app: FrontApp?) async throws {
        let geometry = DisplayGeometry.fromCurrentScreens()
        let windows = (try? await source.shareableWindows()) ?? []
        let flow = Flow(kind: kind, geometry: geometry, context: frontContext(windows: windows, app: app),
                        action: action)
        switch kind {
        case .allInOne:
            try await select(flow, windows: windows, preselected: rect)
        case .selfTimer:
            try await timedArea(rect, flow)
        case .scrolling:
            post(.scrollingCaptureRequested, rect: rect)
        case .text:
            try await recognizeText(rect, stills: [], flow)
        case .area, .previousArea, .window, .fullscreen:
            previousArea.remember(rect)
            await deliver(try await source.captureArea(pointRect: rect), flow)
        }
    }

    func runWindow(ofApp app: String, action: AfterCaptureAction?, front: FrontApp?) async throws {
        let windows = WindowPicker(windows: try await source.shareableWindows()).windows
        let match = windows.first {
            $0.appName?.caseInsensitiveCompare(app) == .orderedSame || $0.bundleIdentifier == app
        }
        guard let window = match else {
            appLog.error("No capturable window for \(app, privacy: .public)")
            throw WindowNotFound(app: app)
        }
        let flow = Flow(kind: .window, geometry: DisplayGeometry.fromCurrentScreens(),
                        context: frontContext(windows: windows, app: front), action: action)
        try await captureWindow(window, flow)
    }

    struct WindowNotFound: LocalizedError {
        let app: String
        var errorDescription: String? { "No capturable window for \(app)." }
    }

    /// Per-capture values handed between the steps of a flow.
    struct Flow {
        let kind: CaptureKind
        let geometry: DisplayGeometry
        let context: FilenameTemplate.Context
        let action: AfterCaptureAction?
    }

    private func deliver(_ image: CapturedImage, _ flow: Flow, as kind: CaptureKind? = nil,
                         context: FilenameTemplate.Context? = nil) async {
        await deliver(image, kind: kind ?? flow.kind, context: context ?? flow.context, action: flow.action)
    }

    // MARK: - Selection overlay

    private func select(_ flow: Flow, windows: [ShareableWindow], preselected: CGRect? = nil) async throws {
        // Frozen stills only when they're shown and used: live mode and the self-timer capture after.
        let freezes = settings.freezeScreen && flow.kind != .selfTimer
        let stills = freezes ? try await source.captureAllDisplays() : []
        let options = SelectionOptions(
            showsStill: freezes,
            showsCrosshair: settings.showCrosshair,
            showsMagnifier: settings.showMagnifier,
            allInOne: flow.kind == .allInOne,
            startMode: flow.kind == .window ? .window : .area,
            previousRect: preselected ?? previousArea.rect(validIn: flow.geometry)
        )
        let overlay = SelectionOverlay(stills: stills, geometry: flow.geometry, windows: windows, options: options)
        switch await overlay.run() {
        case .cancelled:
            appLog.info("Selection cancelled")
        case let .window(window):
            try await captureWindow(window, flow)
        case let .area(rect):
            if flow.kind.remembersArea { previousArea.remember(rect) }
            try await captureSelectedArea(rect, stills: stills, flow)
        case let .allInOne(choice, rect):
            if choice.remembersArea { previousArea.remember(rect) }
            try await runAllInOne(choice, rect: rect, stills: stills, flow)
        }
    }

    private func captureWindow(_ window: ShareableWindow, _ flow: Flow) async throws {
        if flow.kind == .selfTimer {
            guard await selfTimer.countdown(seconds: settings.selfTimerSeconds, around: window.frame) else { return }
        }
        var image = try await source.captureWindow(id: window.id, includeShadow: settings.windowShadow)
        if settings.windowBackground {
            image = await WindowBackground.apply(settings.wallpaper, to: image, around: window.frame)
        }
        let context = FilenameTemplate.Context(app: window.appName ?? flow.context.app, window: window.title)
        await deliver(image, flow, as: .window, context: context)
    }

    private func captureSelectedArea(_ rect: CGRect, stills: [CapturedImage], _ flow: Flow) async throws {
        switch flow.kind {
        case .scrolling:
            await scroll(rect, flow)
        case .text:
            try await recognizeText(rect, stills: stills, flow)
        case .selfTimer:
            try await timedArea(rect, flow)
        case .area, .window, .fullscreen, .previousArea, .allInOne:
            await deliver(try await areaImage(rect, stills: stills, geometry: flow.geometry), flow)
        }
    }

    private func runAllInOne(_ choice: AllInOneChoice, rect: CGRect, stills: [CapturedImage], _ flow: Flow)
        async throws {
        switch choice {
        case .area, .window:
            await deliver(try await areaImage(rect, stills: stills, geometry: flow.geometry), flow)
        case .fullscreen:
            guard let display = flow.geometry.display(bestFor: rect) else { return }
            if settings.freezeScreen, let still = stills.first(where: { $0.displayID == display.id }) {
                await deliver(still, flow, as: .fullscreen)
            } else {
                try await Task.sleep(for: Self.overlayHideDelay)
                await deliver(try await source.captureDisplay(display.id), flow, as: .fullscreen)
            }
        case .scrolling:
            await scroll(rect, flow)
        case .text:
            try await recognizeText(rect, stills: stills, flow)
        case .timer:
            try await timedArea(rect, flow)
        }
    }

    /// Frozen mode cuts the stills taken at shortcut time (composited across displays); live mode
    /// re-captures after the overlay hides.
    private func areaImage(_ rect: CGRect, stills: [CapturedImage], geometry: DisplayGeometry) async throws
        -> CapturedImage {
        if !stills.isEmpty, let image = AreaCompositor.image(of: rect, geometry: geometry, stills: stills) {
            return image
        }
        try await Task.sleep(for: Self.overlayHideDelay)
        return try await source.captureArea(pointRect: rect)
    }

    // MARK: - Other flows

    /// OCR of a selected area, awaited so `--quit` waits for it. Without a handler, posts the rect.
    /// Every path (shortcut, menu, All-In-One, URL region) lands here, and the `.text` History record
    /// is written here rather than in the handler, so its OCR text is searchable (#53, #72).
    private func recognizeText(_ rect: CGRect, stills: [CapturedImage], _ flow: Flow) async throws {
        guard let textHandler else { return post(.captureTextRequested, rect: rect) }
        let image = try await areaImage(rect, stills: stills, geometry: flow.geometry)
        let recordID = await TextCaptureController.addTextRecord(image, context: flow.context, to: history)
        let text = try await textHandler(image.cgImage)
        if let recordID, let history, let text, !text.isEmpty {
            await TextCaptureController.storeText(text, recordID: recordID, in: history)
        }
        record(.delivered)
    }

    private func timedArea(_ rect: CGRect, _ flow: Flow) async throws {
        guard await selfTimer.countdown(seconds: settings.selfTimerSeconds, around: rect) else {
            appLog.info("Self-timer cancelled")
            return
        }
        try await Task.sleep(for: Self.overlayHideDelay)
        await deliver(try await source.captureArea(pointRect: rect), flow, as: .selfTimer)
    }

    /// The display under the cursor, or every display as separate files.
    private func captureFullscreen(_ flow: Flow) async throws {
        if settings.fullscreenAllDisplays {
            for image in try await source.captureAllDisplays() {
                await deliver(image, flow)
            }
            return
        }
        let mouse = NSEvent.mouseLocation
        guard let display = flow.geometry.display(containing: mouse) ?? flow.geometry.primaryDisplay else {
            throw CaptureError.areaOffScreen(CGRect(origin: mouse, size: .zero))
        }
        await deliver(try await source.captureDisplay(display.id), flow)
    }

    /// Scrolling capture runs inside this capture task, so `--quit` waits for it.
    private func scroll(_ rect: CGRect, _ flow: Flow) async {
        guard let scrollingHandler else { return post(.scrollingCaptureRequested, rect: rect) }
        try? await Task.sleep(for: Self.overlayHideDelay)
        await scrollingHandler(rect, flow.context, flow.action)
    }

    /// Hands a region to a feature another worker owns (scrolling, OCR).
    private func post(_ name: Notification.Name, rect: CGRect) {
        appLog.notice("Posting \(name.rawValue, privacy: .public) for \(String(describing: rect), privacy: .public)")
        NotificationCenter.default.post(name: name, object: self, userInfo: ["rect": NSValue(rect: rect)])
    }
}

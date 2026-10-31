import AppKit
import ScreenCapKit

/// Quick Access overlay (PLAN §3.2): a stack of floating thumbnails in a screen corner.
///
/// Receives `.overlay` captures from the sink router. Close marks the history record closed so
/// Restore Recently Closed can bring it back; Delete removes it from history.
@MainActor
final class QuickAccessController: CaptureSink {
    let settings: AppSettings
    let output: CaptureOutput
    let history: HistoryStore?
    /// For handing captures to the editor and pin features once they're installed.
    weak var router: CaptureSinkRouter?
    /// Newest first.
    private(set) var items: [QuickAccessItem] = []
    private var screen: NSScreen?
    private var ticker: Timer?
    /// Coalesces concurrent saves of one capture (+Commands).
    let saveGate = QuickAccessSaveGate<QuickAccessSaveKey>()

    init(settings: AppSettings, output: CaptureOutput, history: HistoryStore?, router: CaptureSinkRouter?) {
        self.settings = settings
        self.output = output
        self.history = history
        self.router = router
        try? FileManager.default.removeItem(at: QuickAccessItem.temporaryFolder)
        observe(.toggleOverlaysRequested) { $0.toggleHidden() }
        observe(.restoreRecentlyClosedRequested) { $0.restoreRecentlyClosed() }
        observe(NSApplication.didChangeScreenParametersNotification) { $0.layout() }
        observe(.addQuickAccessOverlayRequested) { controller, info in
            controller.showRequested(url: info?[AutomationKey.url] as? URL,
                                     recordID: info?[AutomationKey.recordID] as? UUID)
        }
    }

    func deliver(_ result: CaptureResult, action: AfterCaptureAction) async {
        guard QuickAccessPreferences.showAfterCapture else {
            do {
                let url = try await output.save(result)
                appLog.notice("Quick Access off; saved \(url.path, privacy: .public)")
            } catch {
                appLog.error("Save failed: \(error.localizedDescription, privacy: .public)")
            }
            return
        }
        show(result)
    }

    /// Adds a panel for `result` nearest the corner and slides it in.
    func show(_ result: CaptureResult) {
        if QuickAccessVisibility.isHidden { setHidden(false) }
        let options = settings.quickAccess
        let size = QuickAccessLayout.panelSize(imageSize: result.image.pixelSize, size: options.size)
        let panel = QuickAccessPanel(image: result.image.cgImage, size: size)
        let item = QuickAccessItem(result: result, panel: panel,
                                   timer: AutoCloseTimer(seconds: options.autoCloseSeconds, now: Date()))
        wire(item)
        item.refreshInfo()
        items.insert(item, at: 0)
        screen = targetScreen()
        layout(entering: item)
        startTicker()
        let saveOptions = settings.saveOptions
        item.prepareTask = Task { [weak item] in
            let contents = await QuickAccessItem.prepareDrag(for: result, options: saveOptions)
            item?.drag = contents
        }
    }

    /// Removes a panel and closes the gap. `markClosed` records it for Restore Recently Closed.
    func remove(_ item: QuickAccessItem, markClosed: Bool) {
        guard let index = items.firstIndex(where: { $0 === item }) else { return }
        items.remove(at: index)
        item.prepareTask?.cancel()
        let panel = item.panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            panel.orderOut(nil)
        }
        if markClosed, let id = item.result.historyRecordID, let history {
            Task { _ = try? await history.markClosed(id: id) }
        }
        layout()
        if items.isEmpty { stopTicker() }
    }

    // MARK: - Layout

    /// Puts every panel at its stack position; `entering` slides in from the edge.
    func layout(entering: QuickAccessItem? = nil) {
        if let current = screen, !NSScreen.screens.contains(current) { screen = targetScreen() }
        guard let visible = (screen ?? targetScreen())?.visibleFrame else { return }
        let corner = settings.quickAccess.position
        let frames = QuickAccessLayout.frames(for: items.map(\.panel.frame.size), corner: corner, in: visible)
        for (item, frame) in zip(items, frames) {
            item.baseFrame = frame
            if item === entering {
                item.panel.setFrame(QuickAccessLayout.entryFrame(for: frame, corner: corner), display: false)
                item.panel.alphaValue = 0
                if !QuickAccessVisibility.isHidden { item.panel.orderFrontRegardless() }
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                item.panel.animator().setFrame(frame, display: true)
                item.panel.animator().alphaValue = 1
            }
        }
    }

    private func targetScreen() -> NSScreen? {
        switch settings.quickAccess.display {
        case .withCursor:
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.screens.first
        case .main:
            return NSScreen.screens.first
        }
    }

    // MARK: - Hide, restore, auto-close

    func toggleHidden() { setHidden(!QuickAccessVisibility.isHidden) }

    /// Hides or shows every panel; timers pause while hidden.
    func setHidden(_ hidden: Bool) {
        QuickAccessVisibility.isHidden = hidden
        let now = Date()
        for item in items {
            if hidden {
                item.isHovered = false
                item.timer.pause(at: now)
                item.panel.orderOut(nil)
            } else {
                item.timer.resume(at: now)
                item.panel.orderFrontRegardless()
            }
        }
    }

    /// Re-shows the most recently closed capture from history.
    func restoreRecentlyClosed() {
        guard let history else { return }
        Task {
            guard let closed = await history.recentlyClosed(limit: 1).first else {
                appLog.notice("Nothing recently closed to restore")
                return
            }
            showRequested(url: nil, recordID: closed.id)
        }
    }

    /// Shows a file or history record (URL scheme, History → Restore). The record only leaves
    /// Restore Recently Closed once its panel is actually on screen.
    func showRequested(url: URL?, recordID: UUID?) {
        Task {
            guard let result = await QuickAccessSource.result(url: url, recordID: recordID, history: history) else {
                let name = url?.path ?? recordID?.uuidString ?? "nothing"
                appLog.error("Quick Access couldn't open \(name, privacy: .public)")
                HUDPanel.show("Couldn't open image")
                return
            }
            show(result)
            if let id = result.historyRecordID, let history {
                _ = try? await history.restore(id: id)
            }
            NotificationCenter.default.post(name: .historyRecordsChanged, object: nil)
        }
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        let now = Date()
        for item in items where item.timer.isExpired(at: now) {
            remove(item, markClosed: true)
        }
    }

    private func observe(_ name: Notification.Name, _ handler: @escaping @MainActor (QuickAccessController) -> Void) {
        observe(name) { controller, _ in handler(controller) }
    }

    private func observe(_ name: Notification.Name,
                         _ handler: @escaping @MainActor (QuickAccessController, [AnyHashable: Any]?) -> Void) {
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            // userInfo isn't Sendable; the queue is main, so it never leaves this thread.
            nonisolated(unsafe) let info = note.userInfo
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self, info)
            }
        }
    }
}

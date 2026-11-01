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
    /// Drag-out copies; each panel's are removed when it goes (#114).
    let temp: TempFiles
    /// "+N" for panels past the cap (#116); made on first use.
    private var badge: QuickAccessBadge?

    init(settings: AppSettings, output: CaptureOutput, history: HistoryStore?, router: CaptureSinkRouter?,
         temp: TempFiles? = nil) {
        self.settings = settings
        self.output = output
        self.history = history
        self.router = router
        self.temp = temp ?? .shared
        observe(.toggleOverlaysRequested) { $0.toggleHidden() }
        observe(.restoreRecentlyClosedRequested) { $0.restoreRecentlyClosed() }
        observe(.focusQuickAccessRequested) { $0.focusNewest() }
        observe(NSApplication.didChangeScreenParametersNotification) { $0.layout() }
        observe(.addQuickAccessOverlayRequested) { controller, info in
            controller.showRequested(url: info?[AutomationKey.url] as? URL,
                                     recordID: info?[AutomationKey.recordID] as? UUID)
        }
    }

    /// Always shows the panel. "Show after capture" off is handled upstream: the coordinator turns
    /// `.overlay` into `.save`, which surfaces its own failures (#75, #105).
    func deliver(_ result: CaptureResult, action: AfterCaptureAction) async {
        show(result)
    }

    /// Adds a panel for `result` nearest the corner and slides it in.
    func show(_ result: CaptureResult) {
        if QuickAccessVisibility.isHidden { setHidden(false) }
        let options = settings.quickAccess
        let size = QuickAccessLayout.panelSize(imageSize: result.image.pixelSize, size: options.size)
        let panel = QuickAccessPanel(image: result.image.cgImage, size: size)
        // A capture History couldn't store never closes on its own (#113).
        let seconds = result.historyWriteFailed ? nil : options.autoCloseSeconds
        let item = QuickAccessItem(result: result, panel: panel, timer: AutoCloseTimer(seconds: seconds, now: Date()))
        wire(item)
        item.refreshInfo()
        items.insert(item, at: 0)
        screen = targetScreen()
        layout(entering: item)
        startTicker()
        prepareDrag(for: item)
    }

    /// Writes the drag-out copy in the background and tracks it under the panel. A panel that
    /// closed meanwhile (task cancelled) has its copy removed at once (#114).
    private func prepareDrag(for item: QuickAccessItem) {
        let saveOptions = settings.saveOptions
        let result = item.result
        let owner = item.tempOwner
        item.prepareTask = Task { [weak item, temp] in
            let contents = await QuickAccessItem.prepareDrag(for: result, options: saveOptions, in: temp.launchFolder)
            guard let folder = contents.fileURL?.deletingLastPathComponent() else {
                item?.drag = contents
                return
            }
            guard !Task.isCancelled, let item else {
                try? FileManager.default.removeItem(at: folder)
                return
            }
            temp.track(folder, owner: owner, record: result.historyRecordID)
            item.drag = contents
        }
    }

    /// History records of the panels on screen, newest first (the quit path marks them closed, #103).
    var openRecordIDs: [UUID] { items.compactMap(\.result.historyRecordID) }

    /// Removes a panel and closes the gap. `markClosed` records it for Restore Recently Closed.
    func remove(_ item: QuickAccessItem, markClosed: Bool) {
        guard let index = items.firstIndex(where: { $0 === item }) else { return }
        items.remove(at: index)
        item.prepareTask?.cancel()
        temp.release(item.tempOwner)
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

    /// Puts the newest panels (up to the cap) at their stack positions, inside the screen's
    /// visible frame; older ones wait behind the "+N" badge (#116). `entering` slides in.
    func layout(entering: QuickAccessItem? = nil) {
        if let current = screen, !NSScreen.screens.contains(current) { screen = targetScreen() }
        guard let visible = (screen ?? targetScreen())?.visibleFrame else { return }
        let corner = settings.quickAccess.position
        let stack = QuickAccessLayout.stack(for: items.map(\.panel.frame.size), corner: corner, in: visible)
        let now = Date()
        for item in items.dropFirst(stack.frames.count) where !item.isOverflowed {
            item.isOverflowed = true
            item.isHovered = false
            item.timer.pause(at: now)
            item.panel.orderOut(nil)
        }
        updateBadge(stack)
        for (item, frame) in zip(items, stack.frames) {
            let returning = item.isOverflowed
            if returning {
                item.isOverflowed = false
                if !QuickAccessVisibility.isHidden { item.timer.resume(at: now) }
            }
            item.baseFrame = frame
            if returning, item !== entering {
                item.panel.setFrame(frame, display: false)
                item.panel.alphaValue = 0
                if !QuickAccessVisibility.isHidden { item.panel.orderFrontRegardless() }
            }
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

    private func updateBadge(_ stack: QuickAccessLayout.Stack) {
        guard let frame = stack.badgeFrame else {
            badge?.orderOut(nil)
            return
        }
        let badge = badge ?? QuickAccessBadge()
        self.badge = badge
        badge.setCount(stack.hiddenCount)
        badge.setFrame(frame, display: true)
        if !QuickAccessVisibility.isHidden { badge.orderFrontRegardless() }
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
        for item in items where !item.isOverflowed {
            if hidden {
                item.isHovered = false
                item.timer.pause(at: now)
                item.panel.orderOut(nil)
            } else {
                item.timer.resume(at: now)
                item.panel.orderFrontRegardless()
            }
        }
        if hidden {
            badge?.orderOut(nil)
        } else if items.contains(where: \.isOverflowed) {
            badge?.orderFrontRegardless()
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
        for item in items where item.timer.isExpired(at: now) && !item.isOnlyCopy {
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

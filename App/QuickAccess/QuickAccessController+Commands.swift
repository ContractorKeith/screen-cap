import AppKit
import ScreenCapKit

// Toolbar buttons, hover, swipes and drag-out for one panel.
extension QuickAccessController {
    func wire(_ item: QuickAccessItem) {
        let thumbnail = item.panel.thumbnail
        thumbnail.toolbar.onCommand = { [weak self, weak item] command in
            guard let self, let item else { return }
            perform(command, on: item)
        }
        thumbnail.onHover = { [weak item] hovered in
            guard let item, !QuickAccessVisibility.isHidden else { return }
            item.isHovered = hovered
            if hovered { item.timer.pause(at: Date()) } else { item.timer.resume(at: Date()) }
        }
        thumbnail.onDoubleClick = { [weak self, weak item] in
            guard let self, let item else { return }
            perform(.annotate, on: item)
        }
        thumbnail.dragContents = { [weak self, weak item] in
            guard let self, let item else { return QuickAccessDragContents() }
            return item.dragContents(scale: settings.retinaScale)
        }
        thumbnail.onSwipeChanged = { [weak item] dx in
            guard let item else { return }
            item.panel.setFrameOrigin(CGPoint(x: item.baseFrame.minX + dx, y: item.baseFrame.minY))
        }
        thumbnail.onSwipeEnded = { [weak self, weak item] tracker in
            guard let self, let item else { return }
            finishSwipe(tracker, on: item)
        }
        thumbnail.onSwipeCancelled = { [weak self] in self?.layout() }
        wireKeyboard(item)
    }

    /// Key presses and focus changes while the panel is key (#129).
    private func wireKeyboard(_ item: QuickAccessItem) {
        item.panel.onKey = { [weak self, weak item] event in
            guard let self, let item else { return false }
            return handleKey(event, on: item)
        }
        item.panel.onFocusChange = { [weak item] focused in
            guard let item else { return }
            item.isFocused = focused
            item.panel.thumbnail.isFocused = focused
            if focused {
                item.timer.pause(at: Date())
            } else if !item.isHovered, !QuickAccessVisibility.isHidden {
                item.timer.resume(at: Date())
            }
        }
    }

    func perform(_ command: QuickAccessCommand, on item: QuickAccessItem) {
        let refocus = item.isFocused ? visibleItems.firstIndex { $0 === item } : nil
        switch command {
        case .copy: Task { await copy(item) }
        case .save: Task { await save(item) }
        case .annotate: handOff(item, to: router?.annotate, action: .annotate, notification: .openAnnotateRequested)
        case .pin: handOff(item, to: router?.pin, action: .pin, notification: .pinRequested)
        case .ocr: requestText(item)
        case .reveal: Task { await reveal(item) }
        case .close: Task { await close(item); focusAfterRemoving(item, at: refocus) }
        case .delete: Task { await delete(item); focusAfterRemoving(item, at: refocus) }
        }
    }

    // MARK: - Keyboard (#129)

    /// Panels on screen (not behind the "+N" badge), newest first.
    private var visibleItems: [QuickAccessItem] { items.filter { !$0.isOverflowed } }

    /// Focus Quick Access: makes the newest panel key, showing hidden overlays first.
    func focusNewest() {
        if QuickAccessVisibility.isHidden { setHidden(false) }
        guard let newest = visibleItems.first else {
            HUDPanel.show("No Quick Access captures")
            return
        }
        newest.panel.focusForKeyboard()
    }

    private func handleKey(_ event: NSEvent, on item: QuickAccessItem) -> Bool {
        guard let action = QuickAccessKeys.action(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers,
                                                  modifiers: event.modifierFlags,
                                                  corner: settings.quickAccess.position)
        else { return false }
        switch action {
        case let .command(command):
            perform(command, on: item)
        case .next, .previous:
            let visible = visibleItems
            guard let index = visible.firstIndex(where: { $0 === item }) else { return true }
            visible[QuickAccessKeys.move(from: index, by: action, count: visible.count)].panel.focusForKeyboard()
        }
        return true
    }

    /// A focused panel that closed hands focus to the panel now in its place, so a keyboard user
    /// can work down the stack. Nothing happens if the panel stayed (Cancel in the close prompt).
    private func focusAfterRemoving(_ item: QuickAccessItem, at index: Int?) {
        guard let index, !items.contains(where: { $0 === item }) else { return }
        let visible = visibleItems
        guard !visible.isEmpty else { return }
        visible[min(index, visible.count - 1)].panel.focusForKeyboard()
    }

    private func finishSwipe(_ tracker: SwipeTracker, on item: QuickAccessItem) {
        switch tracker.action(for: settings.quickAccess.position) {
        case .dismiss:
            Task { await close(item) }
        case .save:
            Task {
                if await save(item) != nil { remove(item, markClosed: true) } else { layout() }
            }
        case nil:
            layout()
        }
    }

    /// Close and the dismiss swipe. A capture that exists only in this panel (History couldn't
    /// store it, #113) asks first: Save, Close Without Saving, or Cancel.
    private func close(_ item: QuickAccessItem) async {
        guard item.isOnlyCopy else {
            remove(item, markClosed: true)
            return
        }
        switch QuickAccessClosePrompt.ask() {
        case .save:
            if await save(item) != nil { remove(item, markClosed: true) } else { layout() }
        case .discard:
            remove(item, markClosed: true)
        case .cancel:
            layout()
        }
    }

    /// Panels whose capture would be lost on quit (#113).
    var onlyCopies: [QuickAccessItem] { items.filter(\.isOnlyCopy) }

    /// Saves every panel that is the only copy of its capture. True when all saved.
    func saveOnlyCopies() async -> Bool {
        var allSaved = true
        for item in onlyCopies where await save(item) == nil { allSaved = false }
        return allSaved
    }

    private func copy(_ item: QuickAccessItem) async {
        do {
            try await output.copy(item.result)
            item.flash("Copied")
        } catch {
            item.flash("Copy failed")
            appLog.error("Copy failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Saves once; later calls return the existing file. A save already running is shared, and
    /// the Save button is off until it finishes (#78).
    @discardableResult
    func save(_ item: QuickAccessItem) async -> URL? {
        if let url = item.savedURL { return url }
        let key = saveKey(item)
        let toolbar = item.panel.thumbnail.toolbar
        toolbar.setEnabled(false, for: .save)
        defer { if !saveGate.isSaving(key) { toolbar.setEnabled(true, for: .save) } }
        return await saveGate.save(key) { [output] in
            do {
                let url = try await output.save(item.result)
                item.savedURL = url
                item.savedBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
                item.refreshInfo()
                appLog.notice("Saved \(url.path, privacy: .public)")
                return url
            } catch {
                item.flash("Save failed")
                appLog.error("Save failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    func saveKey(_ item: QuickAccessItem) -> QuickAccessSaveKey {
        item.result.historyRecordID.map(QuickAccessSaveKey.record) ?? .panel(ObjectIdentifier(item))
    }

    /// Saves first if needed, then selects the file in Finder.
    private func reveal(_ item: QuickAccessItem) async {
        guard let url = await save(item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Removes the record from history and moves a file saved from this panel to the Trash.
    /// Either failing shows why in a HUD (#105); the panel is already gone by then.
    private func delete(_ item: QuickAccessItem) async {
        remove(item, markClosed: false)
        // Copy-as-file copies of this capture go too (#114).
        if let id = item.result.historyRecordID { temp.release(records: [id]) }
        let deleteRecord: (() async throws -> Void)? = item.result.historyRecordID.flatMap { id in
            history.map { history in { _ = try await history.delete(id: id) } }
        }
        // A save still running lands after the panel is gone; wait for it so its file is trashed too.
        let pending = await saveGate.pending(saveKey(item))
        let message = await QuickAccessDeletion.run(deleteRecord: deleteRecord, fileURL: item.savedURL ?? pending) {
            try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
        }
        if let message {
            appLog.error("Delete failed: \(message, privacy: .public)")
            HUDPanel.show(message, duration: .seconds(4))
        }
    }

    /// Uses the installed feature when there is one (and closes the panel); otherwise posts
    /// the request for that feature to observe and keeps the panel open.
    private func handOff(_ item: QuickAccessItem, to sink: CaptureSink?, action: AfterCaptureAction,
                         notification: Notification.Name) {
        if let sink {
            Task { await sink.deliver(item.result, action: action) }
            remove(item, markClosed: true)
            return
        }
        var info: [String: Any] = [QuickAccessUserInfo.result: item.result]
        if let url = item.savedURL { info[QuickAccessUserInfo.fileURL] = url }
        NotificationCenter.default.post(name: notification, object: nil, userInfo: info)
    }

    private func requestText(_ item: QuickAccessItem) {
        var info: [String: Any] = [
            QuickAccessUserInfo.image: item.result.image.cgImage,
            QuickAccessUserInfo.result: item.result
        ]
        if let id = item.result.historyRecordID { info[QuickAccessUserInfo.recordID] = id }
        NotificationCenter.default.post(name: .captureTextRequested, object: nil, userInfo: info)
    }
}

/// The ask-before-closing alert for a capture History couldn't store (#113).
@MainActor
enum QuickAccessClosePrompt {
    enum Choice { case save, discard, cancel }

    static func ask(count: Int = 1, quitting: Bool = false) -> Choice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = count == 1
            ? "Save this capture before closing?"
            : "Save \(count) captures before quitting?"
        alert.informativeText = "History couldn't store \(count == 1 ? "it" : "them"), so "
            + (quitting ? "quitting" : "closing") + " without saving loses \(count == 1 ? "it" : "them") for good."
        alert.addButton(withTitle: count == 1 ? "Save" : "Save All")
        alert.addButton(withTitle: quitting ? "Quit Without Saving" : "Close Without Saving")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertSecondButtonReturn: return .discard
        default: return .cancel
        }
    }
}

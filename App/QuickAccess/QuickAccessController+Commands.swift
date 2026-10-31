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
        thumbnail.dragContents = { [weak item] in item?.dragContents() ?? QuickAccessDragContents() }
        thumbnail.onSwipeChanged = { [weak item] dx in
            guard let item else { return }
            item.panel.setFrameOrigin(CGPoint(x: item.baseFrame.minX + dx, y: item.baseFrame.minY))
        }
        thumbnail.onSwipeEnded = { [weak self, weak item] tracker in
            guard let self, let item else { return }
            finishSwipe(tracker, on: item)
        }
    }

    func perform(_ command: QuickAccessCommand, on item: QuickAccessItem) {
        switch command {
        case .copy: Task { await copy(item) }
        case .save: Task { await save(item) }
        case .annotate: handOff(item, to: router?.annotate, action: .annotate, notification: .openAnnotateRequested)
        case .pin: handOff(item, to: router?.pin, action: .pin, notification: .pinRequested)
        case .ocr: requestText(item)
        case .reveal: Task { await reveal(item) }
        case .close: remove(item, markClosed: true)
        case .delete: Task { await delete(item) }
        }
    }

    private func finishSwipe(_ tracker: SwipeTracker, on item: QuickAccessItem) {
        switch tracker.action(for: settings.quickAccess.position) {
        case .dismiss:
            remove(item, markClosed: true)
        case .save:
            Task {
                if await save(item) != nil { remove(item, markClosed: true) } else { layout() }
            }
        case nil:
            layout()
        }
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
    private func save(_ item: QuickAccessItem) async -> URL? {
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
    private func delete(_ item: QuickAccessItem) async {
        remove(item, markClosed: false)
        if let id = item.result.historyRecordID, let history {
            _ = try? await history.delete(id: id)
        }
        // A save still running lands after the panel is gone; wait for it so its file is trashed too.
        let pending = await saveGate.pending(saveKey(item))
        if let url = item.savedURL ?? pending {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
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

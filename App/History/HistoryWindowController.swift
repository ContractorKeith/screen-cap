import AppKit
import ScreenCapKit
import SwiftUI
import UniformTypeIdentifiers

/// The History window (PLAN §3.4). Opens on `.openHistoryRequested` (shortcut, menu, URL scheme).
@MainActor
final class HistoryWindowController {
    let model: HistoryViewModel
    private let settings: AppSettings
    private var window: NSWindow?
    private var observers: [NSObjectProtocol] = []

    init(store: HistoryStore?, settings: AppSettings) {
        self.settings = settings
        self.model = HistoryViewModel(store: store, retentionDays: { [settings] in settings.historyRetentionDays })
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .openHistoryRequested, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.show() }
        })
        // Quick Access restores and OCR change records while the window may be open.
        observers.append(center.addObserver(
            forName: .historyRecordsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let model = self?.model else { return }
                Task { await model.reload() }
            }
        })
    }

    func show() {
        if window == nil {
            let view = HistoryView(model: model, actions: HistoryActions(settings: settings, model: model))
            let newWindow = NSWindow(contentViewController: NSHostingController(rootView: view))
            newWindow.title = "Capture History"
            newWindow.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            newWindow.setContentSize(CGSize(width: 860, height: 600))
            newWindow.contentMinSize = CGSize(width: 520, height: 360)
            newWindow.isReleasedWhenClosed = false
            newWindow.setFrameAutosaveName("ScreenCapHistory")
            newWindow.center()
            window = newWindow
        }
        Task { await model.reload() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// AppKit side effects for history records.
@MainActor
struct HistoryActions {
    let settings: AppSettings
    let model: HistoryViewModel

    func openInEditor(_ record: CaptureRecord) {
        NotificationCenter.default.post(name: .openAnnotateRequested, object: nil,
                                        userInfo: [AutomationKey.url: record.fileURL])
    }

    /// Copies as image or file per the Copy mode setting.
    func copy(_ records: [CaptureRecord]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch settings.copyMode {
        case .file:
            pasteboard.writeObjects(records.map { $0.fileURL as NSURL })
        case .image:
            pasteboard.writeObjects(records.compactMap { NSImage(contentsOf: $0.fileURL) })
        }
    }

    func saveAs(_ record: CaptureRecord) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: record.fileURL.pathExtension) ?? .png]
        panel.directoryURL = settings.saveFolder
        let context = FilenameTemplate.Context(app: record.appName, window: record.windowTitle)
        // Name it like a fresh save, but keep the stored file's extension (history stores PNG).
        let name = settings.saveOptions.template(clock: { record.createdAt }).filename(context: context)
        panel.nameFieldStringValue = (name as NSString).deletingPathExtension + "." + record.fileURL.pathExtension
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            try FileManager.default.copyItem(at: record.fileURL, to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func reveal(_ records: [CaptureRecord]) {
        NSWorkspace.shared.activateFileViewerSelecting(records.map(\.fileURL))
    }

    func delete(_ ids: Set<UUID>) {
        Task { await model.delete(ids) }
    }

    /// Shows the closed records in Quick Access, which marks them open once shown.
    func restore(_ ids: Set<UUID>) {
        for record in model.restorable(ids) {
            NotificationCenter.default.post(name: .addQuickAccessOverlayRequested, object: nil, userInfo: [
                AutomationKey.url: record.fileURL, AutomationKey.recordID: record.id
            ])
        }
    }

    func purge() {
        Task { await model.purge() }
    }
}

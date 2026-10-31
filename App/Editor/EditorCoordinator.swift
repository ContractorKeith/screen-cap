import AppKit
import ScreenCapKit
import UniformTypeIdentifiers

extension Notification.Name {
    // `openAnnotateRequested` is shared; see App/Automation/AutomationNotifications.swift.
    /// Menu: Annotate ▸ Open Image…
    static let openEditorImageRequested = Notification.Name("ScreenCapOpenEditorImageRequested")
    /// Menu: Annotate ▸ Open from Clipboard…
    static let openEditorClipboardRequested = Notification.Name("ScreenCapOpenEditorClipboardRequested")
}

/// Opens editor windows: the `.annotate` capture sink, Quick Access requests and the menu rows.
@MainActor
final class EditorCoordinator: CaptureSink {
    private let settings: AppSettings
    private let preferences: EditorPreferences
    private var windows: [EditorWindowController] = []
    private var observers: [NSObjectProtocol] = []

    init(settings: AppSettings, preferences: EditorPreferences = .shared) {
        self.settings = settings
        self.preferences = preferences
        observe()
    }

    /// Creates the coordinator for `AppDelegate.installFeatures()`.
    static func install(settings: AppSettings) -> EditorCoordinator {
        EditorCoordinator(settings: settings)
    }

    func deliver(_ result: CaptureResult, action: AfterCaptureAction) async {
        open(result)
    }

    func open(_ result: CaptureResult) {
        let model = EditorDocumentModel(snapshot: EditorSnapshot(image: result.image.cgImage,
                                                                 scale: Double(result.image.scale)))
        model.filenameContext = result.context
        show(model)
    }

    func open(_ url: URL) {
        do {
            show(try EditorDocumentModel.open(url))
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// Asks for an image or `.screencap` file.
    func openImagePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .image, EditorWindowController.projectType]
        // Info.plist exports the .screencap package type; this still covers `swift run`, where it isn't registered.
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.message = "Choose an image or a ScreenCap project to annotate."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func openClipboard() {
        guard let image = NSImage(pasteboard: .general),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            NSAlert(error: EditorError.noImageOnClipboard).runModal()
            return
        }
        let scale = image.size.width > 0 ? max(1, (Double(cgImage.width) / image.size.width).rounded()) : 1
        show(EditorDocumentModel(snapshot: EditorSnapshot(image: cgImage, scale: scale)))
    }

    // MARK: - Quit

    private var quitReview: UnsavedReview<ObjectIdentifier>?

    /// `applicationShouldTerminate`: quits now when nothing is unsaved; otherwise asks about each
    /// unsaved window in turn and calls `reply` with the verdict (Cancel or a failed save stops).
    func reviewUnsavedBeforeQuit(reply: @escaping @MainActor (Bool) -> Void) -> NSApplication.TerminateReply {
        guard quitReview == nil else { return .terminateCancel } // a review is already on screen
        let review = UnsavedReview(dirty: windows.filter(\.hasUnsavedChanges).map(ObjectIdentifier.init))
        guard case .ask = review.firstStep else { return .terminateNow }
        quitReview = review
        advanceQuitReview(review.firstStep, reply: reply)
        return .terminateLater
    }

    private func advanceQuitReview(_ step: UnsavedReview<ObjectIdentifier>.Step,
                                   reply: @escaping @MainActor (Bool) -> Void) {
        switch step {
        case let .ask(id):
            guard let controller = windows.first(where: { ObjectIdentifier($0) == id }) else {
                // Closed meanwhile: nothing left to lose there.
                advanceQuitReview(recordQuitOutcome(.discarded), reply: reply)
                return
            }
            controller.reviewBeforeQuit { [weak self] outcome in
                guard let self else { return }
                self.advanceQuitReview(self.recordQuitOutcome(outcome), reply: reply)
            }
        case .terminate, .cancel:
            quitReview = nil
            reply(step == .terminate)
        }
    }

    private func recordQuitOutcome(_ outcome: UnsavedOutcome) -> UnsavedReview<ObjectIdentifier>.Step {
        quitReview?.record(outcome) ?? .cancel
    }

    private func show(_ model: EditorDocumentModel) {
        let controller = EditorWindowController(model: model, settings: settings, preferences: preferences)
        controller.onClose = { [weak self] closed in self?.windows.removeAll { $0 === closed } }
        windows.append(controller)
        controller.show()
    }

    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .openAnnotateRequested, object: nil, queue: .main) { note in
            let result = note.userInfo?["result"] as? CaptureResult
            let url = note.userInfo?["url"] as? URL
            MainActor.assumeIsolated { [weak self] in
                if let result { self?.open(result) } else if let url { self?.open(url) }
            }
        })
        observers.append(center.addObserver(forName: .openEditorImageRequested, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { [weak self] in self?.openImagePanel() }
        })
        observers.append(center.addObserver(forName: .openEditorClipboardRequested, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { [weak self] in self?.openClipboard() }
        })
    }
}

/// The status-menu rows for the editor; `AppMenu` adds them as one submenu.
@MainActor
enum EditorMenu {
    static var entries: [MenuEntry] {
        [
            .item(MenuAction("Open Image…") {
                NotificationCenter.default.post(name: .openEditorImageRequested, object: nil)
            }),
            .item(MenuAction("Open from Clipboard…") {
                NotificationCenter.default.post(name: .openEditorClipboardRequested, object: nil)
            })
        ]
    }
}

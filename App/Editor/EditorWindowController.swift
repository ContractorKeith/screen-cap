import AppKit
import ScreenCapKit
import SwiftUI

/// Window-level UI state that isn't part of the document.
@MainActor
@Observable
final class EditorUIState {
    enum Panel: String, CaseIterable { case style = "Style", background = "Background" }

    var panel: Panel = .style
    /// Short confirmation shown in the toolbar ("Copied", "Saved to Desktop").
    var status: String?
    var showsTransformSheet = false
}

/// One editor window: hosts the SwiftUI chrome around the AppKit canvas and runs file commands.
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let model: EditorDocumentModel
    let chrome = EditorUIState()
    let settings: AppSettings
    let preferences: EditorPreferences
    let canvas: CanvasView
    let scrollView: NSScrollView
    /// Called when the window closes, so the coordinator can release it.
    var onClose: ((EditorWindowController) -> Void)?

    init(model: EditorDocumentModel, settings: AppSettings, preferences: EditorPreferences) {
        self.model = model
        self.settings = settings
        self.preferences = preferences
        canvas = CanvasView(model: model)
        scrollView = Self.makeScrollView(documentView: canvas)
        let window = EditorWindow(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 760),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
        window.minSize = CGSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        window.keyMenu = EditorKeyMenu.make()
        model.tool = preferences.initialTool
        model.options = preferences.toolOptions
        model.onChange = { [weak self] in self?.modelDidChange() }
        window.contentView = NSHostingView(rootView: EditorView(controller: self))
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func makeScrollView(documentView: NSView) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.contentView = CenteringClipView()
        scrollView.documentView = documentView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = ZoomMath.minimum
        scrollView.maxMagnification = ZoomMath.maximum
        scrollView.backgroundColor = .underPageBackgroundColor
        scrollView.drawsBackground = true
        return scrollView
    }

    func show() {
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(canvas)
        // Fit once the hosting view has laid out the scroll view.
        DispatchQueue.main.async { [weak self] in self?.zoomToFit(nil) }
        detectTextIfNeeded()
    }

    /// Finds text in a new base image, for automatic "Use as redaction" flags.
    private func detectTextIfNeeded() {
        guard model.detectedText?.image !== model.baseImage, model.textDetection == nil else { return }
        Task { [model] in await model.detectedTextLines() }
    }

    private func modelDidChange() {
        canvas.modelDidChange()
        detectTextIfNeeded()
        updateTitle()
        if preferences.rememberLastTool, model.tool != .crop { preferences.lastTool = model.tool }
    }

    private func updateTitle() {
        let name = model.fileURL?.deletingPathExtension().lastPathComponent ?? "Annotate"
        window?.title = name
        window?.isDocumentEdited = model.isDirty
        window?.representedURL = model.fileURL
    }

    /// Shows `message` in the toolbar for two seconds.
    func flash(_ message: String) {
        chrome.status = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.chrome.status == message { self?.chrome.status = nil }
        }
    }

    func present(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    // MARK: - Zoom

    @objc func zoomIn(_ sender: Any?) { setMagnification(ZoomMath.zoomIn(from: scrollView.magnification)) }
    @objc func zoomOut(_ sender: Any?) { setMagnification(ZoomMath.zoomOut(from: scrollView.magnification)) }

    @objc func zoomToActualSize(_ sender: Any?) {
        setMagnification(1 / max(model.document.baseImage.scale, 1))
    }

    @objc func zoomToFit(_ sender: Any?) {
        let fit = ZoomMath.fit(content: model.document.canvasSize, in: scrollView.contentSize,
                               maxScale: 1 / max(model.document.baseImage.scale, 1))
        setMagnification(fit)
    }

    private func setMagnification(_ value: Double) {
        canvas.commitTextEditing()
        let center = CGPoint(x: canvas.visibleRect.midX, y: canvas.visibleRect.midY)
        scrollView.setMagnification(ZoomMath.clamp(value), centeredAt: center)
        canvas.needsDisplay = true
    }

    // MARK: - Close

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard hasUnsavedChanges else { return true }
        UnsavedChangesPrompt.show(for: sender, quitting: false) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .saved: self.saveDocument { saved in if saved { self.forceClose() } }
            case .discarded: self.forceClose()
            case .cancelled: break
            }
        }
        return false
    }

    func forceClose() {
        window?.delegate = nil
        window?.close()
        onClose?(self)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
    }
}

/// Editor window that routes shortcuts through a private key menu, since the app has no main menu.
final class EditorWindow: NSWindow {
    var keyMenu: NSMenu?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyMenu?.performKeyEquivalent(with: event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// Clip view that keeps a canvas smaller than the viewport centered.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        let frame = document.frame
        if rect.width > frame.width { rect.origin.x = (frame.width - rect.width) / 2 }
        if rect.height > frame.height { rect.origin.y = (frame.height - rect.height) / 2 }
        return rect
    }
}

/// Shortcuts for the editor window. Actions go to the first responder: the canvas (or the text
/// view while editing text), then the window controller.
@MainActor
enum EditorKeyMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        let items: [Shortcut] = [
            Shortcut("Save", "s", .command, #selector(EditorWindowController.saveDocument(_:))),
            Shortcut("Save As", "s", [.command, .shift], #selector(EditorWindowController.saveDocumentAs(_:))),
            Shortcut("Export", "e", .command, #selector(EditorWindowController.exportImage(_:))),
            Shortcut("Copy Image", "c", [.command, .shift], #selector(EditorWindowController.copyImage(_:))),
            Shortcut("Close", "w", .command, #selector(NSWindow.performClose(_:))),
            Shortcut("Undo", "z", .command, #selector(CanvasView.undo(_:))),
            Shortcut("Redo", "z", [.command, .shift], #selector(CanvasView.redo(_:))),
            Shortcut("Cut", "x", .command, #selector(CanvasView.cut(_:))),
            Shortcut("Copy", "c", .command, #selector(CanvasView.copy(_:))),
            Shortcut("Paste", "v", .command, #selector(CanvasView.paste(_:))),
            Shortcut("Duplicate", "d", .command, #selector(CanvasView.duplicate(_:))),
            Shortcut("Select All", "a", .command, #selector(NSResponder.selectAll(_:))),
            Shortcut("Bring Forward", "]", .command, #selector(CanvasView.bringForward(_:))),
            Shortcut("Send Backward", "[", .command, #selector(CanvasView.sendBackward(_:))),
            Shortcut("Bring to Front", "]", [.command, .option], #selector(CanvasView.bringToFront(_:))),
            Shortcut("Send to Back", "[", [.command, .option], #selector(CanvasView.sendToBack(_:))),
            Shortcut("Zoom In", "=", .command, #selector(EditorWindowController.zoomIn(_:))),
            Shortcut("Zoom In", "+", .command, #selector(EditorWindowController.zoomIn(_:))),
            Shortcut("Zoom Out", "-", .command, #selector(EditorWindowController.zoomOut(_:))),
            Shortcut("Zoom to Fit", "0", .command, #selector(EditorWindowController.zoomToFit(_:))),
            Shortcut("Actual Size", "1", .command, #selector(EditorWindowController.zoomToActualSize(_:)))
        ]
        for shortcut in items {
            let item = NSMenuItem(title: shortcut.title, action: shortcut.action, keyEquivalent: shortcut.key)
            item.keyEquivalentModifierMask = shortcut.modifiers
            menu.addItem(item)
        }
        return menu
    }

    struct Shortcut {
        var title: String
        var key: String
        var modifiers: NSEvent.ModifierFlags
        var action: Selector

        init(_ title: String, _ key: String, _ modifiers: NSEvent.ModifierFlags, _ action: Selector) {
            (self.title, self.key, self.modifiers, self.action) = (title, key, modifiers, action)
        }
    }
}

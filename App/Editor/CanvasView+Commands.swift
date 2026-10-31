import AppKit
import ScreenCapKit

// Keyboard, edit commands (reached through the editor's key menu and the responder chain),
// the context menu, and image drops.

extension CanvasView: NSMenuItemValidation {
    override func keyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        let step = shift ? 10.0 : 1.0
        switch event.specialKey {
        case .leftArrow?: nudge(CGSize(width: -step, height: 0))
        case .rightArrow?: nudge(CGSize(width: step, height: 0))
        case .upArrow?: nudge(CGSize(width: 0, height: -step))
        case .downArrow?: nudge(CGSize(width: 0, height: step))
        case .delete?, .deleteForward?, .backspace?: model.deleteSelection()
        case .carriageReturn?, .enter?: returnPressed()
        default: handleCharacterKey(event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        if model.tool == .crop { model.cancelCrop() } else { model.selection = []; model.touch() }
    }

    private func nudge(_ offset: CGSize) {
        model.moveSelection(by: offset, groupKey: "nudge")
    }

    private func returnPressed() {
        if model.tool == .crop {
            model.applyCrop()
        } else if let selected = model.singleSelection, case .text = selected.kind {
            beginTextEditing(selected.id)
        }
    }

    /// Single-letter tool shortcuts (no modifiers).
    private func handleCharacterKey(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard modifiers.isEmpty, let character = event.charactersIgnoringModifiers?.lowercased().first,
              let tool = EditorTool.allCases.first(where: { $0.key == character }) else {
            super.keyDown(with: event)
            return
        }
        if tool == .crop { model.beginCrop() } else { model.tool = tool }
    }

    // MARK: - Edit commands

    @objc func copy(_ sender: Any?) {
        guard let payload = model.clipboardPayload(), let data = try? JSONEncoder().encode(payload) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: NSPasteboard.PasteboardType(AnnotationClipboard.pasteboardType))
    }

    @objc func cut(_ sender: Any?) {
        copy(sender)
        model.deleteSelection()
    }

    /// Pastes copied annotations, or an image from the pasteboard as a new image layer.
    @objc func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: NSPasteboard.PasteboardType(AnnotationClipboard.pasteboardType)),
           let payload = try? JSONDecoder().decode(AnnotationClipboard.self, from: data) {
            model.tool = .select
            model.paste(payload)
        } else if let image = NSImage(pasteboard: pasteboard)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            model.tool = .select
            model.addImageLayer(image)
        }
    }

    @objc func delete(_ sender: Any?) { model.deleteSelection() }
    @objc func duplicate(_ sender: Any?) { model.duplicateSelection() }
    @objc override func selectAll(_ sender: Any?) { model.tool = .select; model.selectAll() }
    @objc func bringForward(_ sender: Any?) { model.arrange(.forward) }
    @objc func sendBackward(_ sender: Any?) { model.arrange(.backward) }
    @objc func bringToFront(_ sender: Any?) { model.arrange(.front) }
    @objc func sendToBack(_ sender: Any?) { model.arrange(.back) }

    /// While text is being edited, undo belongs to the text view.
    @objc func undo(_ sender: Any?) {
        if let editor = textEditor { editor.undoManager?.undo() } else { model.undo() }
    }

    @objc func redo(_ sender: Any?) {
        if let editor = textEditor { editor.undoManager?.redo() } else { model.redo() }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): textEditor != nil || model.canUndo
        case #selector(redo(_:)): textEditor != nil || model.canRedo
        case #selector(copy(_:)), #selector(cut(_:)), #selector(delete(_:)), #selector(duplicate(_:)),
             #selector(bringForward(_:)), #selector(sendBackward(_:)), #selector(bringToFront(_:)),
             #selector(sendToBack(_:)):
            !model.selection.isEmpty
        default: true
        }
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = imagePoint(event)
        if let hit = EditorGeometry.topmost(in: model.document, at: point, tolerance: tolerance),
           !model.selection.contains(hit) {
            model.selection = [hit]
            model.touch()
        }
        guard !model.selection.isEmpty else { return nil }
        let menu = NSMenu()
        let items: [(String, Selector)] = [
            ("Bring Forward", #selector(bringForward(_:))), ("Send Backward", #selector(sendBackward(_:))),
            ("Bring to Front", #selector(bringToFront(_:))), ("Send to Back", #selector(sendToBack(_:))),
            ("-", #selector(delete(_:))),
            ("Copy", #selector(copy(_:))), ("Duplicate", #selector(duplicate(_:))), ("Delete", #selector(delete(_:)))
        ]
        for (title, action) in items {
            if title == "-" { menu.addItem(.separator()); continue }
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    // MARK: - Image drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        NSImage.canInit(with: sender.draggingPasteboard) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let image = NSImage(pasteboard: sender.draggingPasteboard)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        let point = convert(sender.draggingLocation, from: nil)
        model.tool = .select
        model.addImageLayer(image, center: CGPoint(x: point.x - imageFrame.minX, y: point.y - imageFrame.minY))
        window?.makeFirstResponder(self)
        return true
    }
}

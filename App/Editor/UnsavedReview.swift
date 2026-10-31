import AppKit

// Quit with unsaved editor windows (#73): ask about each one, Cancel aborts the quit.

/// What the user did with one unsaved document.
enum UnsavedOutcome: Equatable {
    case saved
    case discarded
    /// Cancel in the prompt, or a save that didn't finish (save panel cancelled, write failed).
    case cancelled
}

/// The review-unsaved decision logic, kept pure for tests: which document to ask about next,
/// and whether the app may quit.
struct UnsavedReview<ID: Hashable> {
    enum Step: Equatable {
        case ask(ID)
        case terminate
        case cancel
    }

    private var pending: [ID]

    /// `dirty`: the unsaved documents, in the order to ask about them.
    init(dirty: [ID]) {
        pending = dirty
    }

    /// Ask about the first document, or quit at once when nothing is unsaved.
    var firstStep: Step {
        pending.first.map(Step.ask) ?? .terminate
    }

    /// Records the answer for the document last asked about and returns the next step.
    mutating func record(_ outcome: UnsavedOutcome) -> Step {
        guard !pending.isEmpty else { return .terminate }
        switch outcome {
        case .cancelled:
            pending.removeAll()
            return .cancel
        case .saved, .discarded:
            pending.removeFirst()
            return firstStep
        }
    }
}

/// The "Save changes?" sheet shared by closing a window and quitting. Return saves, ⌘D doesn't
/// save, Esc cancels, and ⌘S saves too, as it does in the editor.
@MainActor
enum UnsavedChangesPrompt {
    static func show(for window: NSWindow, quitting: Bool, answer: @escaping @MainActor (UnsavedOutcome) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Save changes to this screenshot?"
        alert.informativeText = quitting
            ? "ScreenCap is quitting. Your annotations will be lost if you don’t save them."
            : "Your annotations will be lost if you don’t save them."
        let save = alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don’t Save")
        // ⌘S while the sheet is up presses Save.
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === alert.window,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers?.lowercased() == "s" else { return event }
            save.performClick(nil)
            return nil
        }
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                if let monitor { NSEvent.removeMonitor(monitor) }
                switch response {
                case .alertFirstButtonReturn: answer(.saved)
                case .alertThirdButtonReturn: answer(.discarded)
                default: answer(.cancelled)
                }
            }
        }
    }
}

extension EditorWindowController {
    /// True when quitting should ask about this window.
    var hasUnsavedChanges: Bool {
        canvas.commitTextEditing()
        return model.isDirty
    }

    /// Brings the window forward and asks whether to save it before quitting. `.saved` only once
    /// the project is written.
    func reviewBeforeQuit(_ done: @escaping @MainActor (UnsavedOutcome) -> Void) {
        guard let window, window.attachedSheet == nil else {
            // Already showing a sheet (a save panel or the close prompt): let the user finish there.
            window?.makeKeyAndOrderFront(nil)
            done(.cancelled)
            return
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        UnsavedChangesPrompt.show(for: window, quitting: true) { [weak self] outcome in
            guard let self, outcome == .saved else { done(outcome); return }
            self.saveDocument { saved in done(saved ? .saved : .cancelled) }
        }
    }
}

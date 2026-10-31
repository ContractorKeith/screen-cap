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

/// Turns the prompt's answer into an outcome: Save runs `save` and reports `.saved` only once
/// it finishes (`.cancelled` if it doesn't); the other answers pass straight through.
@MainActor
enum UnsavedChangesFlow {
    static func resolve(_ answer: UnsavedOutcome,
                        save: (@escaping @MainActor (Bool) -> Void) -> Void,
                        done: @escaping @MainActor (UnsavedOutcome) -> Void) {
        guard answer == .saved else { done(answer); return }
        save { saved in done(saved ? .saved : .cancelled) }
    }
}

/// A window the quit review asks about.
@MainActor
protocol UnsavedQuitReviewable: AnyObject {
    var hasUnsavedChanges: Bool { get }
    /// Asks Save / Don't Save / Cancel and calls `done` exactly once with the result.
    func reviewBeforeQuit(_ done: @escaping @MainActor (UnsavedOutcome) -> Void)
}

/// Runs one quit review at a time over the open windows and replies to the terminate request
/// exactly once. After a Cancel the next quit starts a fresh review.
@MainActor
final class QuitReviewer {
    private var review: UnsavedReview<ObjectIdentifier>?
    private let windows: @MainActor () -> [any UnsavedQuitReviewable]

    /// `windows`: the open windows, read again at each step since one may close meanwhile.
    init(windows: @escaping @MainActor () -> [any UnsavedQuitReviewable]) {
        self.windows = windows
    }

    var isReviewing: Bool { review != nil }

    /// `applicationShouldTerminate`: quits now when nothing is unsaved; otherwise asks about each
    /// unsaved window in turn and calls `reply` with the verdict (Cancel or a failed save stops).
    func start(reply: @escaping @MainActor (Bool) -> Void) -> NSApplication.TerminateReply {
        guard review == nil else { return .terminateCancel } // a review is already on screen
        let fresh = UnsavedReview(dirty: windows().filter(\.hasUnsavedChanges).map(ObjectIdentifier.init))
        guard case .ask = fresh.firstStep else { return .terminateNow }
        review = fresh
        advance(fresh.firstStep, reply: reply)
        return .terminateLater
    }

    private func advance(_ step: UnsavedReview<ObjectIdentifier>.Step, reply: @escaping @MainActor (Bool) -> Void) {
        switch step {
        case let .ask(id):
            guard let window = windows().first(where: { ObjectIdentifier($0) == id }) else {
                // Closed meanwhile: nothing left to lose there.
                advance(record(.discarded), reply: reply)
                return
            }
            window.reviewBeforeQuit { [weak self] outcome in
                guard let self else { return }
                self.advance(self.record(outcome), reply: reply)
            }
        case .terminate, .cancel:
            review = nil
            reply(step == .terminate)
        }
    }

    private func record(_ outcome: UnsavedOutcome) -> UnsavedReview<ObjectIdentifier>.Step {
        review?.record(outcome) ?? .cancel
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

extension EditorWindowController: UnsavedQuitReviewable {
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
        UnsavedChangesPrompt.show(for: window, quitting: true) { [weak self] answer in
            guard let self else { done(.cancelled); return }
            UnsavedChangesFlow.resolve(answer, save: { self.performSave(completion: $0) }, done: done)
        }
    }
}

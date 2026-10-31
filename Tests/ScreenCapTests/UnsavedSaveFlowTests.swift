import AppKit
@testable import ScreenCap
import Testing

// #97: Save in the unsaved-changes prompt must finish: the completion runs, the window closes,
// and the quit gets exactly one terminate reply. Cancel replies false and a later quit still works.
@Suite("Unsaved-changes Save completes")
@MainActor
struct UnsavedSaveFlowTests {
    /// Stands in for `performSave(completion:)`: records each save and finishes it on demand.
    @MainActor
    final class FakeSaver {
        var pending: [@MainActor (Bool) -> Void] = []
        var saves = 0
        var succeeds = true

        func save(_ done: @escaping @MainActor (Bool) -> Void) {
            saves += 1
            pending.append(done)
        }

        /// Finishes the saves started so far, as the async write would.
        func finish() {
            let finishing = pending
            pending.removeAll()
            finishing.forEach { $0(succeeds) }
        }
    }

    /// An unsaved window whose prompt answers `answer`, then goes through the real flow.
    @MainActor
    final class FakeWindow: UnsavedQuitReviewable {
        var hasUnsavedChanges = true
        var answer: UnsavedOutcome
        let saver: FakeSaver
        var asked = 0

        init(answer: UnsavedOutcome, saver: FakeSaver) {
            self.answer = answer
            self.saver = saver
        }

        func reviewBeforeQuit(_ done: @escaping @MainActor (UnsavedOutcome) -> Void) {
            asked += 1
            UnsavedChangesFlow.resolve(answer, save: saver.save) { outcome in
                if outcome == .saved { self.hasUnsavedChanges = false }
                done(outcome)
            }
        }
    }

    @Test func saveRunsTheCompletionOnceTheWriteFinishes() {
        let saver = FakeSaver()
        var outcomes: [UnsavedOutcome] = []
        UnsavedChangesFlow.resolve(.saved, save: saver.save) { outcomes.append($0) }
        #expect(saver.saves == 1)
        #expect(outcomes.isEmpty) // not before the write is done
        saver.finish()
        #expect(outcomes == [.saved])

        saver.succeeds = false
        UnsavedChangesFlow.resolve(.saved, save: saver.save) { outcomes.append($0) }
        saver.finish()
        #expect(outcomes == [.saved, .cancelled])

        UnsavedChangesFlow.resolve(.discarded, save: saver.save) { outcomes.append($0) }
        #expect(saver.saves == 2)
        #expect(outcomes == [.saved, .cancelled, .discarded])
    }

    @Test func quitAfterSavingEveryWindowRepliesTerminateOnce() {
        let saver = FakeSaver()
        let windows = [FakeWindow(answer: .saved, saver: saver), FakeWindow(answer: .discarded, saver: saver),
                       FakeWindow(answer: .saved, saver: saver)]
        let reviewer = QuitReviewer { windows }
        var replies: [Bool] = []

        #expect(reviewer.start { replies.append($0) } == .terminateLater)
        #expect(replies.isEmpty)
        saver.finish() // first window's save
        #expect(windows.map(\.asked) == [1, 1, 1])
        saver.finish() // third window's save
        #expect(replies == [true])
        #expect(saver.saves == 2)
        #expect(!reviewer.isReviewing)
    }

    @Test func cancelRepliesFalseAndALaterQuitStillWorks() {
        let saver = FakeSaver()
        let window = FakeWindow(answer: .cancelled, saver: saver)
        let reviewer = QuitReviewer { [window] }
        var replies: [Bool] = []

        #expect(reviewer.start { replies.append($0) } == .terminateLater)
        #expect(replies == [false])
        #expect(!reviewer.isReviewing)

        // A failed save also refuses the quit and frees the reviewer.
        window.answer = .saved
        saver.succeeds = false
        #expect(reviewer.start { replies.append($0) } == .terminateLater)
        saver.finish()
        #expect(replies == [false, false])

        saver.succeeds = true
        #expect(reviewer.start { replies.append($0) } == .terminateLater)
        saver.finish()
        #expect(replies == [false, false, true])
        // Nothing unsaved now: the next quit goes through at once.
        #expect(reviewer.start { replies.append($0) } == .terminateNow)
        #expect(replies == [false, false, true])
    }

    @Test func secondQuitDuringAReviewIsRefusedWithoutAnotherReply() {
        let saver = FakeSaver()
        let reviewer = QuitReviewer { [FakeWindow(answer: .saved, saver: saver)] }
        var replies: [Bool] = []
        #expect(reviewer.start { replies.append($0) } == .terminateLater)
        #expect(reviewer.start { replies.append($0) } == .terminateCancel)
        saver.finish()
        #expect(replies == [true])
    }
}

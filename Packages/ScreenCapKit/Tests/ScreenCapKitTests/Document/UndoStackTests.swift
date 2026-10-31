import Foundation
@testable import ScreenCapKit
import Testing

@Suite("UndoStack")
struct UndoStackTests {
    @Test func undoRedo() {
        var stack = UndoStack(0)
        #expect(!stack.canUndo && !stack.canRedo)
        stack.record(1)
        stack.record(2)
        #expect(stack.undo() == 1)
        #expect(stack.undo() == 0)
        #expect(stack.undo() == nil)
        #expect(stack.canRedo)
        #expect(stack.redo() == 1)
        #expect(stack.current == 1)
        stack.record(5)
        #expect(!stack.canRedo)
        #expect(stack.undo() == 1)
    }

    @Test func coalescesSameGroupKey() {
        var stack = UndoStack(0)
        stack.record(1, groupKey: "drag")
        stack.record(2, groupKey: "drag")
        stack.record(3, groupKey: "drag")
        #expect(stack.undoCount == 1)
        stack.record(4, groupKey: "type")
        #expect(stack.undoCount == 2)
        #expect(stack.undo() == 3)
        #expect(stack.undo() == 0)
    }

    @Test func groupClosesAfterUndoOrEndGrouping() {
        var stack = UndoStack(0)
        stack.record(1, groupKey: "drag")
        stack.endGrouping()
        stack.record(2, groupKey: "drag")
        #expect(stack.undoCount == 2)
        stack.undo()
        stack.record(3, groupKey: "drag")
        #expect(stack.undoCount == 2)
        #expect(stack.undo() == 1)
    }

    @Test func nilKeyNeverCoalesces() {
        var stack = UndoStack(0)
        stack.record(1)
        stack.record(2)
        #expect(stack.undoCount == 2)
    }

    @Test func maxDepthDropsOldest() {
        var stack = UndoStack(0, maxDepth: 3)
        for value in 1...5 { stack.record(value) }
        #expect(stack.undoCount == 3)
        while stack.canUndo { stack.undo() }
        #expect(stack.current == 2)
    }

    @Test func performWithDocument() {
        var stack = UndoStack(Document(baseImage: DocumentFixtures.base))
        stack.perform { $0.add(DocumentFixtures.counter(1)) }
        let id = stack.current.annotations[0].id
        for _ in 0..<10 {
            stack.perform(groupKey: "move-\(id)") { $0.move(id, by: CGSize(width: 1, height: 0)) }
        }
        #expect(stack.undoCount == 2)
        stack.undo()
        #expect(stack.current.annotations[0].kind.bounds.minX == -10)
        stack.undo()
        #expect(stack.current.annotations.isEmpty)
    }
}

@Suite("UndoStack distinct limit")
struct UndoStackDistinctLimitTests {
    /// States are (buffer id, edit count); many edits can share one buffer.
    @Test func keepsAtMostLimitDistinctKeys() {
        var stack = UndoStack((buffer: 0, edit: 0))
        for buffer in 1...50 {
            stack.record((buffer: buffer, edit: 0))
            stack.record((buffer: buffer, edit: 1))
            stack.limitDistinct(3) { $0.buffer }
        }
        #expect(Set(stack.allStates.map(\.buffer)) == [48, 49, 50])
        // Steps sharing a kept buffer stay undoable; the oldest kept buffer's first step is the floor.
        var undos = 0
        while stack.undo() != nil { undos += 1 }
        #expect(undos == 5)
        #expect(stack.current.buffer == 48 && stack.current.edit == 0)
    }

    @Test func sharedBuffersDoNotCount() {
        var stack = UndoStack((buffer: 0, edit: 0))
        for edit in 1...20 {
            stack.record((buffer: 0, edit: edit))
            stack.limitDistinct(1) { $0.buffer }
        }
        #expect(stack.undoCount == 20)
    }
}

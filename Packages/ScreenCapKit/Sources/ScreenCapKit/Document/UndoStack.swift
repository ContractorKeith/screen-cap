import Foundation

/// Value-based undo/redo: each entry is a full snapshot of `State`.
///
/// Consecutive `record` calls with the same non-nil `groupKey` coalesce into one undo step
/// (e.g. a drag that fires many moves). Any undo, redo, `record` with a different key, or
/// `endGrouping()` closes the group.
public struct UndoStack<State: Sendable>: Sendable {
    public private(set) var current: State
    public let maxDepth: Int

    private var undoStates: [State] = []
    private var redoStates: [State] = []
    private var openGroupKey: String?

    public init(_ initial: State, maxDepth: Int = 100) {
        precondition(maxDepth > 0, "maxDepth must be positive")
        current = initial
        self.maxDepth = maxDepth
    }

    public var canUndo: Bool { !undoStates.isEmpty }
    public var canRedo: Bool { !redoStates.isEmpty }
    public var undoCount: Int { undoStates.count }
    public var redoCount: Int { redoStates.count }

    /// Makes `newState` current. Pushes the old state as an undo step unless this call
    /// continues the open group. Clears redo.
    public mutating func record(_ newState: State, groupKey: String? = nil) {
        let continuesGroup = groupKey != nil && groupKey == openGroupKey && canUndo
        if !continuesGroup {
            undoStates.append(current)
            if undoStates.count > maxDepth { undoStates.removeFirst(undoStates.count - maxDepth) }
        }
        current = newState
        redoStates.removeAll()
        openGroupKey = groupKey
    }

    /// Applies `change` to a copy of the current state and records the result.
    public mutating func perform(groupKey: String? = nil, _ change: (inout State) throws -> Void) rethrows {
        var next = current
        try change(&next)
        record(next, groupKey: groupKey)
    }

    /// Ends the open coalescing group so the next `record` starts a new undo step.
    public mutating func endGrouping() {
        openGroupKey = nil
    }

    @discardableResult
    public mutating func undo() -> State? {
        guard let previous = undoStates.popLast() else { return nil }
        redoStates.append(current)
        current = previous
        openGroupKey = nil
        return current
    }

    @discardableResult
    public mutating func redo() -> State? {
        guard let next = redoStates.popLast() else { return nil }
        undoStates.append(current)
        current = next
        openGroupKey = nil
        return current
    }
}

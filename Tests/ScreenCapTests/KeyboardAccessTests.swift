import AppKit
import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

/// #129: keys in a focused Quick Access panel map to its commands and to moving between panels.
@Suite("Quick Access keyboard")
struct QuickAccessKeyTests {
    private typealias Code = QuickAccessKeys.KeyCode

    private func action(_ code: UInt16, _ chars: String = "", _ mods: NSEvent.ModifierFlags = [],
                        corner: ScreenCorner = .bottomRight) -> QuickAccessKeyAction? {
        QuickAccessKeys.action(keyCode: code, characters: chars, modifiers: mods, corner: corner)
    }

    @Test func commandShortcutsMapToPanelCommands() {
        // Key codes for letters don't matter; the map reads the layout's characters.
        #expect(action(8, "c", .command) == .command(.copy))
        #expect(action(1, "s", .command) == .command(.save))
        #expect(action(14, "e", .command) == .command(.annotate))
        #expect(action(35, "p", .command) == .command(.pin))
        #expect(action(17, "t", .command) == .command(.ocr))
        #expect(action(15, "r", .command) == .command(.reveal))
        #expect(action(13, "w", .command) == .command(.close))
        #expect(action(8, "C", [.command, .capsLock]) == .command(.copy))
    }

    @Test func plainKeysMapToPanelCommands() {
        #expect(action(Code.returnKey) == .command(.annotate))
        #expect(action(Code.enter) == .command(.annotate))
        #expect(action(Code.escape) == .command(.close))
        #expect(action(Code.delete) == .command(.delete))
        #expect(action(Code.forwardDelete) == .command(.delete))
    }

    /// #147: ⌫ on a never-saved capture asks first; a saved one deletes; ⌘⌫ never asks.
    @Test func deleteKeysConfirmOnlyForUnsavedCaptures() {
        func step(_ code: UInt16, _ mods: NSEvent.ModifierFlags = [], saved: Bool) -> QuickAccessDeletion.Step? {
            switch action(code, "", mods) {
            case .command(.delete): QuickAccessDeletion.step(isSaved: saved, confirmed: false)
            case .confirmedDelete: QuickAccessDeletion.step(isSaved: saved, confirmed: true)
            default: nil
            }
        }
        #expect(step(Code.delete, saved: false) == .confirm)
        #expect(step(Code.forwardDelete, saved: false) == .confirm)
        #expect(step(Code.delete, saved: true) == .delete)
        #expect(step(Code.delete, .command, saved: false) == .delete)
        #expect(step(Code.forwardDelete, .command, saved: false) == .delete)
        #expect(step(Code.delete, .command, saved: true) == .delete)
        #expect(action(Code.delete, "", .shift) == nil)
        #expect(QuickAccessKeys.move(from: 1, by: .confirmedDelete, count: 3) == 1)
    }

    @Test func tabMovesBetweenPanels() {
        #expect(action(Code.tab) == .next)
        #expect(action(Code.tab, "", .shift) == .previous)
    }

    @Test func arrowsFollowTheStackDirection() {
        // Bottom corners stack upward: ↑ goes to older panels.
        #expect(action(Code.upArrow, corner: .bottomLeft) == .next)
        #expect(action(Code.downArrow, corner: .bottomLeft) == .previous)
        // Top corners stack downward.
        #expect(action(Code.downArrow, corner: .topRight) == .next)
        #expect(action(Code.upArrow, corner: .topRight) == .previous)
        // Overflow columns grow toward the screen center.
        #expect(action(Code.rightArrow, corner: .bottomLeft) == .next)
        #expect(action(Code.leftArrow, corner: .bottomRight) == .next)
    }

    @Test func unmappedOrModifiedKeysPassThrough() {
        #expect(action(8, "c") == nil) // plain c
        #expect(action(8, "c", [.command, .shift]) == nil)
        #expect(action(8, "c", [.command, .option]) == nil)
        #expect(action(0, "a", .command) == nil)
        #expect(action(Code.returnKey, "", .command) == nil)
        #expect(action(Code.escape, "", .shift) == nil)
        #expect(action(Code.upArrow, "", .command) == nil)
        #expect(action(Code.tab, "", .control) == nil)
    }

    @Test func movingWrapsAroundTheStack() {
        #expect(QuickAccessKeys.move(from: 0, by: .next, count: 3) == 1)
        #expect(QuickAccessKeys.move(from: 2, by: .next, count: 3) == 0)
        #expect(QuickAccessKeys.move(from: 0, by: .previous, count: 3) == 2)
        #expect(QuickAccessKeys.move(from: 0, by: .next, count: 1) == 0)
        #expect(QuickAccessKeys.move(from: 1, by: .command(.copy), count: 3) == 1)
    }

    @Test @MainActor func focusShortcutIsInTheCatalog() {
        let entry = ShortcutCatalog.all.first { $0.command == .focusQuickAccess }
        #expect(entry?.title == "Focus Quick Access")
    }
}

/// #130: arrow keys move the History selection through a row-major grid.
@Suite("History keyboard navigation")
struct HistoryGridMoveTests {
    private func move(_ index: Int?, _ direction: HistoryViewModel.GridMove, columns: Int = 4,
                      count: Int = 10) -> Int? {
        HistoryViewModel.move(from: index, direction, columns: columns, count: count)
    }

    @Test func firstPressLandsOnTheFirstCell() {
        for direction in [HistoryViewModel.GridMove.left, .right, .above, .below] {
            #expect(move(nil, direction) == 0)
        }
        #expect(move(42, .below) == 0) // a cursor that no longer exists
        #expect(move(nil, .below, count: 0) == nil)
    }

    @Test func leftAndRightStepAndStopAtTheEnds() {
        #expect(move(5, .right) == 6)
        #expect(move(5, .left) == 4)
        #expect(move(3, .right) == 4) // wraps to the next row like reading order
        #expect(move(0, .left) == 0)
        #expect(move(9, .right) == 9)
    }

    @Test func upAndDownJumpARow() {
        // 4 columns, 10 cells: rows 0-3, 4-7, 8-9.
        #expect(move(1, .below) == 5)
        #expect(move(5, .above) == 1)
        #expect(move(2, .above) == 2) // top row stays
        #expect(move(8, .below) == 8) // bottom row stays
    }

    @Test func downIntoAShorterLastRowLandsOnItsLastCell() {
        #expect(move(7, .below) == 9)
        #expect(move(5, .below) == 9)
        #expect(move(4, .below) == 8)
    }

    @Test(arguments: 1...6)
    func everyCellIsReachableForAnyColumnCount(columns: Int) {
        let count = 11
        var reached: Set<Int> = []
        var index: Int?
        for _ in 0..<count {
            index = move(index, .right, columns: columns, count: count)
            reached.insert(index ?? -1)
        }
        #expect(reached == Set(0..<count))
        // Down from the top-left walks column 0, then never leaves the grid.
        var row = 0
        for _ in 0..<count {
            row = move(row, .below, columns: columns, count: count) ?? -1
            #expect((0..<count).contains(row))
        }
    }

    @Test func oneColumnMovesLikeAList() {
        #expect(move(2, .below, columns: 1, count: 4) == 3)
        #expect(move(2, .above, columns: 1, count: 4) == 1)
        #expect(move(2, .below, columns: 0, count: 4) == 3) // bad column count treated as one
    }

    @Test func columnCountMatchesTheAdaptiveGrid() {
        #expect(HistoryViewModel.columnCount(width: 0, minimum: 180, spacing: 14) == 1)
        #expect(HistoryViewModel.columnCount(width: 179, minimum: 180, spacing: 14) == 1)
        #expect(HistoryViewModel.columnCount(width: 374, minimum: 180, spacing: 14) == 2)
        #expect(HistoryViewModel.columnCount(width: 373, minimum: 180, spacing: 14) == 1)
        #expect(HistoryViewModel.columnCount(width: 832, minimum: 180, spacing: 14) == 4)
    }

    @Test func cursorMovesSelectOrExtend() {
        let ids = (0..<6).map { _ in UUID() }
        func step(_ cursor: UUID?, _ direction: HistoryViewModel.GridMove) -> UUID? {
            HistoryViewModel.moveCursor(in: ids, from: cursor, direction, columns: 3)
        }
        #expect(step(nil, .below) == ids[0])
        #expect(step(ids[0], .below) == ids[3])
        #expect(step(ids[3], .right) == ids[4])
        #expect(step(ids[4], .above) == ids[1])
        #expect(step(ids[4], .below) == ids[4])
        #expect(HistoryViewModel.moveCursor(in: [], from: nil, .below, columns: 3) == nil)
        #expect(HistoryViewModel.selecting(ids[4], in: [ids[3]], extending: false) == [ids[4]])
        #expect(HistoryViewModel.selecting(ids[4], in: [ids[3]], extending: true) == [ids[3], ids[4]])
    }
}

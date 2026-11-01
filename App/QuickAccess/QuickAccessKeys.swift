import AppKit
import ScreenCapKit

/// What a key press does in a focused Quick Access panel (#129).
enum QuickAccessKeyAction: Equatable {
    case command(QuickAccessCommand)
    /// ⌘⌫ / ⌘⌦: delete without the unsaved-capture prompt (#147).
    case confirmedDelete
    /// Focus the next older panel.
    case next
    /// Focus the next newer panel.
    case previous
}

/// Keyboard map for a focused Quick Access panel, kept pure so it is unit-tested.
/// ⌘C copy, ⌘S save, ⌘E or Return annotate, ⌘P pin, ⌘T copy text, ⌘R show in Finder,
/// ⌫ delete (asks first if never saved, #147), ⌘⌫ delete without asking, Esc close,
/// Tab / ⇧Tab and the arrow keys move between panels.
enum QuickAccessKeys {
    enum KeyCode {
        static let returnKey: UInt16 = 36
        static let tab: UInt16 = 48
        static let delete: UInt16 = 51
        static let escape: UInt16 = 53
        static let enter: UInt16 = 76
        static let forwardDelete: UInt16 = 117
        static let leftArrow: UInt16 = 123
        static let rightArrow: UInt16 = 124
        static let downArrow: UInt16 = 125
        static let upArrow: UInt16 = 126
    }

    /// ⌘ + letter, read from the layout's characters so it follows the keyboard layout.
    private static let commandLetters: [String: QuickAccessCommand] = [
        "c": .copy, "s": .save, "e": .annotate, "p": .pin, "t": .ocr, "r": .reveal, "w": .close
    ]

    /// `characters` is `charactersIgnoringModifiers`; `corner` decides which way the stack grows,
    /// so ↑ means "older" in a bottom corner and "newer" in a top one.
    static func action(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags,
                       corner: ScreenCorner) -> QuickAccessKeyAction? {
        let mods = modifiers.intersection([.command, .shift, .option, .control])
        if let special = specialKey(keyCode, mods: mods, corner: corner) { return special }
        guard mods == .command, let key = characters?.lowercased() else { return nil }
        return commandLetters[key].map(QuickAccessKeyAction.command)
    }

    private static func specialKey(_ keyCode: UInt16, mods: NSEvent.ModifierFlags,
                                   corner: ScreenCorner) -> QuickAccessKeyAction? {
        switch keyCode {
        case KeyCode.tab:
            return mods.isEmpty ? .next : mods == .shift ? .previous : nil
        case KeyCode.returnKey, KeyCode.enter:
            return mods.isEmpty ? .command(.annotate) : nil
        case KeyCode.escape:
            return mods.isEmpty ? .command(.close) : nil
        case KeyCode.delete, KeyCode.forwardDelete:
            return mods.isEmpty ? .command(.delete) : mods == .command ? .confirmedDelete : nil
        case KeyCode.upArrow, KeyCode.downArrow, KeyCode.leftArrow, KeyCode.rightArrow:
            return mods.isEmpty ? arrow(keyCode, corner: corner) : nil
        default:
            return nil
        }
    }

    /// Older panels sit away from the corner: above it in a bottom corner, below it in a top one,
    /// and the next column out toward the screen center.
    private static func arrow(_ keyCode: UInt16, corner: ScreenCorner) -> QuickAccessKeyAction {
        let top = corner == .topLeft || corner == .topRight
        let left = corner == .topLeft || corner == .bottomLeft
        switch keyCode {
        case KeyCode.upArrow: return top ? .previous : .next
        case KeyCode.downArrow: return top ? .next : .previous
        case KeyCode.rightArrow: return left ? .next : .previous
        default: return left ? .previous : .next
        }
    }

    /// Index of the panel to focus after moving from `index` among `count` visible panels; wraps.
    static func move(from index: Int, by action: QuickAccessKeyAction, count: Int) -> Int {
        guard count > 0 else { return 0 }
        switch action {
        case .next: return (index + 1) % count
        case .previous: return (index - 1 + count) % count
        case .command, .confirmedDelete: return index
        }
    }
}

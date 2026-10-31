import AppKit
@preconcurrency import KeyboardShortcuts

/// One row of the status menu, declared as data. Features add rows to `AppMenu.entries`
/// rather than editing `MenuBarController`.
enum MenuEntry {
    case item(MenuAction)
    case submenu(String, [MenuEntry])
    case separator
}

/// A clickable row.
struct MenuAction {
    var title: String
    /// Shows the global shortcut as the item's key hint (kept in sync when the user rebinds it).
    var shortcut: KeyboardShortcuts.Name?
    /// Plain key equivalent with ⌘, e.g. "," for Settings. Ignored when `shortcut` is set.
    var keyEquivalent = ""
    /// Checkmark state, re-read every time the menu opens.
    var isOn: (@MainActor () -> Bool)?
    var perform: @MainActor () -> Void

    init(_ title: String, shortcut: KeyboardShortcuts.Name? = nil, keyEquivalent: String = "",
         isOn: (@MainActor () -> Bool)? = nil, perform: @escaping @MainActor () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.keyEquivalent = keyEquivalent
        self.isOn = isOn
        self.perform = perform
    }
}

/// Turns `MenuEntry` lists into `NSMenu`s.
@MainActor
enum MenuBuilder {
    static func menu(from entries: [MenuEntry], title: String = "") -> NSMenu {
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        for entry in entries {
            menu.addItem(item(for: entry))
        }
        return menu
    }

    private static func item(for entry: MenuEntry) -> NSMenuItem {
        switch entry {
        case .separator:
            return .separator()
        case let .submenu(title, entries):
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = menu(from: entries, title: title)
            return item
        case let .item(action):
            let item = MenuActionHandler.makeItem(action)
            if let shortcut = action.shortcut { item.setShortcut(for: shortcut) }
            return item
        }
    }

    /// Re-reads every checkmark, recursively.
    static func refreshStates(in menu: NSMenu) {
        for item in menu.items {
            (item.representedObject as? MenuActionHandler)?.refresh(item)
            if let submenu = item.submenu { refreshStates(in: submenu) }
        }
    }
}

/// Runs a `MenuAction`. Kept alive as the item's `representedObject` (`target` is weak).
@MainActor
final class MenuActionHandler: NSObject {
    let model: MenuAction

    init(_ model: MenuAction) {
        self.model = model
    }

    static func makeItem(_ model: MenuAction) -> NSMenuItem {
        let handler = MenuActionHandler(model)
        let item = NSMenuItem(title: model.title, action: #selector(fire(_:)), keyEquivalent: model.keyEquivalent)
        item.target = handler
        item.representedObject = handler
        handler.refresh(item)
        return item
    }

    func refresh(_ item: NSMenuItem) {
        if let isOn = model.isOn { item.state = isOn() ? .on : .off }
    }

    @objc func fire(_ sender: Any?) { model.perform() }
}

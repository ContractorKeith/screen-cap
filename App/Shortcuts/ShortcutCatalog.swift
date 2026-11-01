@preconcurrency import KeyboardShortcuts

// Global shortcut names and defaults. Defaults use ⌃⇧ plus a key so they never clash
// with macOS's own ⇧⌘3/4/5 (PLAN §9). Users rebind them in Settings → Shortcuts.
@MainActor
extension KeyboardShortcuts.Name {
    static let captureArea = Self("captureArea", default: .init(.four, modifiers: [.control, .shift]))
    static let captureWindow = Self("captureWindow", default: .init(.w, modifiers: [.control, .shift]))
    static let captureFullscreen = Self("captureFullscreen", default: .init(.three, modifiers: [.control, .shift]))
    static let capturePreviousArea = Self("capturePreviousArea", default: .init(.r, modifiers: [.control, .shift]))
    static let selfTimer = Self("selfTimer", default: .init(.t, modifiers: [.control, .shift]))
    static let allInOne = Self("allInOne", default: .init(.five, modifiers: [.control, .shift]))
    static let scrollingCapture = Self("scrollingCapture", default: .init(.s, modifiers: [.control, .shift]))
    static let captureText = Self("captureText", default: .init(.o, modifiers: [.control, .shift]))
    static let openHistory = Self("openHistory", default: .init(.h, modifiers: [.control, .shift]))
    static let toggleOverlays = Self("toggleOverlays", default: .init(.x, modifiers: [.control, .shift]))
    static let focusQuickAccess = Self("focusQuickAccess", default: .init(.q, modifiers: [.control, .shift]))
}

/// Every global shortcut with its title, in the order Settings shows them.
@MainActor
enum ShortcutCatalog {
    /// What a shortcut does when pressed.
    enum Command: Equatable {
        case capture(CaptureKind)
        case openHistory
        case toggleOverlays
        case focusQuickAccess
    }

    struct Entry {
        let name: KeyboardShortcuts.Name
        let title: String
        let command: Command
    }

    static let all: [Entry] = [
        Entry(name: .captureArea, title: "Capture Area", command: .capture(.area)),
        Entry(name: .captureWindow, title: "Capture Window", command: .capture(.window)),
        Entry(name: .captureFullscreen, title: "Capture Fullscreen", command: .capture(.fullscreen)),
        Entry(name: .capturePreviousArea, title: "Capture Previous Area", command: .capture(.previousArea)),
        Entry(name: .selfTimer, title: "Self-Timer", command: .capture(.selfTimer)),
        Entry(name: .allInOne, title: "All-In-One", command: .capture(.allInOne)),
        Entry(name: .scrollingCapture, title: "Scrolling Capture", command: .capture(.scrolling)),
        Entry(name: .captureText, title: "Capture Text", command: .capture(.text)),
        Entry(name: .openHistory, title: "Open History", command: .openHistory),
        Entry(name: .toggleOverlays, title: "Hide/Show Overlays", command: .toggleOverlays),
        Entry(name: .focusQuickAccess, title: "Focus Quick Access", command: .focusQuickAccess)
    ]

    /// The shortcut name bound to a capture kind, for menu hints.
    static func name(for kind: CaptureKind) -> KeyboardShortcuts.Name? {
        all.first { $0.command == .capture(kind) }?.name
    }

    /// macOS's built-in screenshot shortcuts; our defaults must avoid them.
    static let systemShortcuts: [KeyboardShortcuts.Shortcut] = [
        .init(.three, modifiers: [.command, .shift]),
        .init(.four, modifiers: [.command, .shift]),
        .init(.five, modifiers: [.command, .shift]),
        .init(.six, modifiers: [.command, .shift])
    ]
}

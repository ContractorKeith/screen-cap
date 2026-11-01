@preconcurrency import KeyboardShortcuts
@testable import ScreenCap
import Testing

@Suite("Shortcut defaults")
@MainActor
struct ShortcutCatalogTests {
    @Test func coversEveryNamedShortcut() {
        let names = ShortcutCatalog.all.map(\.name.rawValue)
        #expect(names == [
            "captureArea", "captureWindow", "captureFullscreen", "capturePreviousArea", "selfTimer",
            "allInOne", "scrollingCapture", "captureText", "openHistory", "toggleOverlays", "focusQuickAccess"
        ])
    }

    @Test func defaultsAreUniqueControlShiftCombos() throws {
        let defaults = try ShortcutCatalog.all.map { try #require($0.name.defaultShortcut) }
        #expect(Set(defaults).count == defaults.count)
        for shortcut in defaults {
            #expect(shortcut.modifiers == [.control, .shift])
        }
    }

    @Test func defaultsAvoidSystemScreenshotShortcuts() throws {
        let defaults = try ShortcutCatalog.all.map { try #require($0.name.defaultShortcut) }
        #expect(Set(defaults).isDisjoint(with: ShortcutCatalog.systemShortcuts))
    }

    @Test func everyCaptureKindExceptNoneHasAShortcut() {
        for kind in CaptureKind.allCases {
            #expect(ShortcutCatalog.name(for: kind) != nil, "\(kind) has no shortcut")
        }
    }
}

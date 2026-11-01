import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

/// #117: VoiceOver must read human names, never SF Symbol names.
@Suite("Accessibility labels")
struct AccessibilityLabelTests {
    /// SF Symbol names are lowercase, dotted identifiers like `arrow.up.right` or `pencil.tip`.
    private static func looksLikeSymbol(_ label: String) -> Bool {
        label.contains(".") || label.first?.isLowercase == true
    }

    @Test(arguments: EditorTool.allCases)
    func everyToolHasAHumanLabel(tool: EditorTool) {
        let label = A11y.toolLabel(tool)
        #expect(!label.trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(label != tool.symbol)
        #expect(!Self.looksLikeSymbol(label), "\(tool) reads as \(label)")
        #expect(A11y.toolHint(tool).hasPrefix("Shortcut: "))
    }

    @Test func toolLabelsAreDistinct() {
        let labels = EditorTool.allCases.map(A11y.toolLabel)
        #expect(Set(labels).count == labels.count, "duplicate labels: \(labels)")
    }

    @Test func defaultPaletteSwatchesHaveColorNames() {
        #expect(AppSettings.Defaults.colorPalette.map(A11y.colorName)
                == ["Red", "Yellow", "Green", "Blue", "Purple", "Black", "White"])
        #expect(A11y.colorName(.highlightYellow) == "Yellow, 50% opacity")
        #expect(A11y.colorName(RGBAColor(red: 0.5, green: 0.5, blue: 0.5)) == "Gray")
    }

    @Test @MainActor func afterCaptureLabelsNameTheirRow() {
        let labels = CaptureShortcut.allCases.map { A11y.afterCaptureLabel(GeneralSettingsPane.title(for: $0)) }
        #expect(Set(labels).count == labels.count)
        #expect(labels.first == "After capture: Area")
    }

    @Test func historyThumbnailLabel() {
        let label = A11y.historyThumbnail(kind: "Area", date: Date(timeIntervalSince1970: 0),
                                          source: "Google Chrome", closed: false)
        #expect(label.hasPrefix("Area capture, "))
        #expect(label.hasSuffix(", Google Chrome"))
        #expect(A11y.historyThumbnail(kind: "Window", date: .now, source: nil, closed: true)
            .hasSuffix("closed from Quick Access"))
    }

    @Test func shortcutGlyphsAreSpelledOut() {
        #expect(A11y.spokenShortcut("⌃⇧4") == "Control Shift 4")
        #expect(A11y.spokenShortcut("⌘⌥A") == "Command Option A")
    }

    /// #132: the Resize sheet fields and the retention popup had no AX label.
    @Test func resizeAndRetentionLabels() {
        #expect(A11y.resizeWidth == "Width in pixels")
        #expect(A11y.resizeHeight == "Height in pixels")
        #expect(A11y.historyRetention == "Keep captures for")
    }

    /// #147: the Quick Access unsaved-delete alert.
    @Test func quickAccessDeleteConfirmationLabel() {
        #expect(A11y.quickAccessDeleteConfirmation == "Confirm delete of unsaved capture")
    }

    @Test func otherLabelsAreHuman() {
        let labels = [A11y.arrowStyle, A11y.textStyle, A11y.cropAspect, A11y.inspectorPanel, A11y.pickScreenColor,
                      A11y.addToPalette, A11y.historySearch, A11y.historyGrid, A11y.background("Dusk"),
                      A11y.alignment(.topLeft), A11y.resizeWidth, A11y.resizeHeight, A11y.historyRetention,
                      A11y.quickAccessDeleteConfirmation]
        for label in labels { #expect(!Self.looksLikeSymbol(label), "\(label)") }
    }
}

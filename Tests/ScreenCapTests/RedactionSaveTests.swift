import CoreGraphics
import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

// Saving a project with blur or pixelate bakes them into base.png, after a one-time confirmation (#40).
@Suite("Editor redaction save")
@MainActor
struct RedactionSaveTests {
    private func makeDefaults() -> UserDefaults {
        let name = "RedactionSaveTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func confirmationOnlyWhenRedactionsAndNotYetConfirmed() {
        let model = EditorDocumentModel(snapshot: EditorSnapshot(image: EditorModelTests.image(), scale: 1))
        let defaults = makeDefaults()
        model.add(.counter(number: 1, center: CGPoint(x: 10, y: 10), radius: 6))
        #expect(!model.needsRedactionBakeConfirmation(defaults: defaults))
        model.add(.blur(rect: CGRect(x: 0, y: 0, width: 30, height: 20), mode: .secure, radius: 12))
        #expect(model.needsRedactionBakeConfirmation(defaults: defaults))
        defaults.set(true, forKey: EditorDocumentModel.redactionBakeConfirmedKey)
        #expect(!model.needsRedactionBakeConfirmation(defaults: defaults))
    }

    @Test func savedProjectReopensWithRedactionBaked() throws {
        let model = EditorDocumentModel(snapshot: EditorSnapshot(image: EditorModelTests.image(), scale: 1))
        model.add(.pixelate(rect: CGRect(x: 0, y: 0, width: 40, height: 30), blockSize: 12, randomize: true))
        let counter = model.add(.counter(number: 1, center: CGPoint(x: 55, y: 40), radius: 6))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-\(UUID().uuidString).\(ProjectFile.fileExtension)")
        defer { try? FileManager.default.removeItem(at: url) }
        try model.saveProject(to: url)

        let reopened = try EditorDocumentModel.open(url)
        #expect(reopened.document.annotations.map(\.id) == [counter])
        #expect(!ProjectFile.containsRedactions(reopened.document))
        // The open editor keeps its redaction editable until it's closed.
        #expect(ProjectFile.containsRedactions(model.document))
    }
}

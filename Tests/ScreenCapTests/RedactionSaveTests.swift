import CoreGraphics
import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

// Saving a project with blur or pixelate bakes them into base.png, after a one-time confirmation (#40).
@Suite("Editor redaction save")
@MainActor
struct RedactionSaveTests {
    @Test func confirmationOnlyWhenRedactionsAndNotYetConfirmed() {
        let model = EditorDocumentModel(snapshot: EditorSnapshot(image: EditorModelTests.image(), scale: 1))
        let suite = TemporaryDefaults()
        defer { suite.remove() }
        let defaults = suite.store
        model.add(.counter(number: 1, center: CGPoint(x: 10, y: 10), radius: 6))
        #expect(!model.needsRedactionBakeConfirmation(defaults: defaults))
        model.add(.blur(rect: CGRect(x: 0, y: 0, width: 30, height: 20), mode: .secure, radius: 12))
        #expect(model.needsRedactionBakeConfirmation(defaults: defaults))
        defaults.set(true, forKey: EditorDocumentModel.redactionBakeConfirmedKey)
        #expect(!model.needsRedactionBakeConfirmation(defaults: defaults))
    }
}

// #135: a real bake check on text pixels, not a flat fixture that pixelating can't change.
// An extension of EditorPrivacyTests so it runs serialized with the other Vision test.
extension EditorPrivacyTests {
    @Test func savedProjectReopensWithRedactionBaked() async throws {
        let base = try Self.textImage("Secret 4829 1173 payroll")
        #expect(try await Self.recognized(base).contains("payroll"))
        let model = EditorDocumentModel(snapshot: EditorSnapshot(image: base, scale: 1))
        let rect = CGRect(x: 10, y: 10, width: base.width - 20, height: base.height - 20)
        model.add(.pixelate(rect: rect, blockSize: 24, randomize: true))
        let counter = model.add(.counter(number: 1, center: CGPoint(x: 5, y: 5), radius: 4))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-\(UUID().uuidString).\(ProjectFile.fileExtension)")
        defer { try? FileManager.default.removeItem(at: url) }
        try model.saveProject(to: url)

        // base.png on disk: the text pixels are gone, so OCR finds none of it.
        let saved = try ProjectFile.read(from: url)
        #expect(Self.pixels(saved.baseImage, in: rect) != Self.pixels(base, in: rect))
        let text = try await Self.recognized(saved.baseImage)
        #expect(!text.contains("secret") && !text.contains("payroll") && !text.contains("4829"))

        let reopened = try EditorDocumentModel.open(url)
        #expect(reopened.document.annotations.map(\.id) == [counter])
        #expect(!ProjectFile.containsRedactions(reopened.document))
        // The open editor keeps its redaction editable until it's closed.
        #expect(ProjectFile.containsRedactions(model.document))
    }

    /// RGBA bytes of `rect` (top-left origin), drawn into a fixed sRGB context so encodings compare equal.
    static func pixels(_ image: CGImage, in rect: CGRect) -> [UInt8] {
        let width = Int(rect.width), height = Int(rect.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, // swiftlint:disable:this force_unwrapping
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            let flippedY = CGFloat(image.height) - rect.maxY
            context.draw(image, in: CGRect(x: -rect.minX, y: -flippedY,
                                           width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        return bytes
    }
}

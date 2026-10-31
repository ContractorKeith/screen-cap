import CoreGraphics
import CoreText
import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

// #73 quit review, #74 opaque shapes as redactions, #81 reserved names for Save to Desktop and Share.
// Serialized: Vision requests deadlock when run concurrently on CI runners.
@Suite("Editor quit, redaction and save names", .serialized)
@MainActor
struct EditorPrivacyTests {
    // MARK: - #73 quit review

    @Test func nothingUnsavedQuitsAtOnce() {
        #expect(UnsavedReview<Int>(dirty: []).firstStep == .terminate)
    }

    @Test func asksAboutEachUnsavedDocumentThenQuits() {
        var review = UnsavedReview(dirty: [1, 2, 3])
        #expect(review.firstStep == .ask(1))
        #expect(review.record(.saved) == .ask(2))
        #expect(review.record(.discarded) == .ask(3))
        #expect(review.record(.saved) == .terminate)
    }

    @Test func cancelOrFailedSaveStopsTheQuit() {
        var review = UnsavedReview(dirty: ["a", "b"])
        #expect(review.record(.cancelled) == .cancel)
        var second = UnsavedReview(dirty: ["a", "b"])
        #expect(second.record(.discarded) == .ask("b"))
        #expect(second.record(.cancelled) == .cancel)
    }

    // MARK: - #74 opaque shapes

    @Test func opaqueRectOverTextIsBakedSoOCRFindsNothing() async throws {
        let base = try Self.textImage("Secret 4829 1173 payroll")
        #expect(try await Self.recognized(base).contains("payroll"))
        let model = EditorDocumentModel(snapshot: EditorSnapshot(image: base, scale: 1))
        model.options.style = Annotation.Style(strokeColor: .black, fillColor: .black)
        let bar = model.add(.rectangle(rect: CGRect(x: 10, y: 10, width: base.width - 20, height: base.height - 20),
                                       filled: true, cornerRadius: 0))
        // Off-text opaque shape: automatic flag stays off, so the save warning lists it.
        let swatch = model.add(.ellipse(rect: CGRect(x: 0, y: 0, width: 6, height: 6)))

        await model.detectedTextLines()
        #expect(model.isRedaction(try #require(model.document.annotation(withID: bar))))
        #expect(model.unmarkedOpaqueCovers.map(\.id) == [swatch])
        #expect(model.needsRedactionBakeConfirmation(defaults: UserDefaults(suiteName: UUID().uuidString)!))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("privacy-\(UUID().uuidString).\(ProjectFile.fileExtension)")
        defer { try? FileManager.default.removeItem(at: url) }
        try model.saveProject(to: url)

        let saved = try ProjectFile.read(from: url)
        #expect(saved.document.annotations.map(\.id) == [swatch])
        let text = try await Self.recognized(saved.baseImage)
        #expect(!text.contains("secret") && !text.contains("payroll") && !text.contains("4829"))
        // The open editor keeps the bar editable.
        #expect(model.document.annotation(withID: bar) != nil)
    }

    @Test func toggledOffShapeIsKeptAndNotWarnedAbout() async throws {
        let model = EditorDocumentModel(snapshot: EditorSnapshot(image: EditorModelTests.image(), scale: 1))
        model.options.style = Annotation.Style(strokeColor: .black, fillColor: .black)
        let id = model.add(.rectangle(rect: CGRect(x: 0, y: 0, width: 20, height: 20), filled: true, cornerRadius: 0))
        await model.detectedTextLines()
        #expect(model.unmarkedOpaqueCovers.count == 1)
        model.setRedaction(false, for: [id])
        #expect(model.unmarkedOpaqueCovers.isEmpty)
        #expect(!ProjectFile.containsRedactions(model.documentForSave))
        model.setRedaction(true, for: [id])
        #expect(ProjectFile.containsRedactions(model.documentForSave))
    }

    // MARK: - #81 reserved names

    @Test func reservedWriteNeverOverwritesAnExistingFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("names-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let template = FilenameTemplate("Shot", format: .png)
        let existing = folder.appendingPathComponent("Shot.png")
        try Data("original".utf8).write(to: existing)

        let url = try EditorFileWriter.write(Data("new".utf8), template: template, in: folder)
        #expect(url.lastPathComponent == "Shot 2.png")
        #expect(try Data(contentsOf: existing) == Data("original".utf8))
        #expect(try Data(contentsOf: url) == Data("new".utf8))
    }

    @Test func shareNamesAreLiteralAndReserved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let template = EditorFileWriter.literal("Report {date}")
        let first = try EditorFileWriter.write(Data("a".utf8), template: template, in: folder)
        let second = try EditorFileWriter.write(Data("b".utf8), template: template, in: folder)
        #expect(first.lastPathComponent == "Report (date).png")
        #expect(second.lastPathComponent == "Report (date) 2.png")
        #expect(try Data(contentsOf: first) == Data("a".utf8))
    }

    // MARK: - Fixtures

    /// Black 48 px text on white.
    static func textImage(_ text: String) throws -> CGImage {
        let font = CTFontCreateWithName("Helvetica" as CFString, 48, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let width = 760, height = 120
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.textPosition = CGPoint(x: 30, y: 45)
        CTLineDraw(line, context)
        return try #require(context.makeImage())
    }

    static func recognized(_ image: CGImage) async throws -> String {
        try await TextRecognizer().recognize(in: image).lines.map(\.string).joined(separator: " ").lowercased()
    }
}

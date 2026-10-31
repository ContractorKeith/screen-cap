import CoreGraphics
import Foundation
@testable import ScreenCapKit
import Testing

// Opaque shapes used as redaction bars (#74): marked shapes bake into base.png like blur and pixelate.
// Serialized: Vision + Core Image requests deadlock when run concurrently on CI runners.
@Suite("Opaque-shape redactions", .serialized)
struct OpaqueRedactionTests {
    private static let secret = RedactionTests.textRect
    private static let black = Annotation.Style(strokeColor: .black, fillColor: .black)

    private func document(for base: CGImage, _ annotations: [Annotation]) -> Document {
        var document = Document(baseImage: Document.BaseImage(pixelWidth: base.width, pixelHeight: base.height,
                                                              scale: 1))
        for annotation in annotations { document.add(annotation) }
        return document
    }

    private func tempPackageURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("OpaqueRedaction-\(UUID().uuidString).\(ProjectFile.fileExtension)")
    }

    @Test(arguments: [
        Annotation.Kind.rectangle(rect: secret, filled: true, cornerRadius: 0),
        .ellipse(rect: secret.insetBy(dx: -60, dy: -40)),
        .highlight(region: .rect(rect: secret), color: .black),
        .text(string: "REDACTED", preset: TextPreset.filledBackground.rawValue, fontSize: 30, rect: secret)
    ])
    func markedOpaqueShapeIsBakedAndOCRFindsNothing(kind: Annotation.Kind) throws {
        let base = try EffectsFixtures.textImage(RedactionTests.text)
        #expect(try RedactionTests.leakedWords(in: base).count >= 2)
        let shape = Annotation(style: Self.black, kind: kind, redaction: true)
        let url = tempPackageURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try ProjectFile.write(document(for: base, [shape]), baseImage: base, to: url)

        let contents = try ProjectFile.read(from: url)
        #expect(contents.document.annotations.isEmpty)
        #expect(try RedactionTests.leakedWords(in: contents.baseImage).isEmpty)
    }

    @Test func shapeMarkedOffStaysEditableAndKeepsOriginal() throws {
        let base = try EffectsFixtures.textImage(RedactionTests.text)
        let shape = Annotation(style: Self.black, kind: .rectangle(rect: Self.secret, filled: true, cornerRadius: 0),
                               redaction: false)
        let url = tempPackageURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try ProjectFile.write(document(for: base, [shape]), baseImage: base, to: url)

        let contents = try ProjectFile.read(from: url)
        #expect(contents.document.annotations == [shape])
        #expect(try RedactionTests.leakedWords(in: contents.baseImage).count >= 2)
    }

    @Test func opaqueCoverRules() {
        func cover(_ kind: Annotation.Kind, _ style: Annotation.Style = Self.black) -> Bool {
            Annotation(style: style, kind: kind).isOpaqueCover
        }
        let rect = CGRect(x: 0, y: 0, width: 50, height: 20)
        #expect(cover(.rectangle(rect: rect, filled: true, cornerRadius: 0)))
        #expect(!cover(.rectangle(rect: rect, filled: false, cornerRadius: 0), Annotation.Style()))
        #expect(!cover(.rectangle(rect: rect, filled: true, cornerRadius: 0),
                       Annotation.Style(fillColor: .black, opacity: 0.8)))
        #expect(!cover(.ellipse(rect: rect), Annotation.Style()))
        #expect(cover(.highlight(region: .rect(rect: rect), color: .black)))
        #expect(!cover(.highlight(region: .rect(rect: rect), color: RGBAColor(red: 1, green: 0.9, blue: 0.2))))
        #expect(!cover(.highlight(region: .rect(rect: rect), color: .highlightYellow)))
        #expect(!cover(.text(string: "x", preset: TextPreset.plain.rawValue, fontSize: 12, rect: rect)))
        #expect(cover(.text(string: "x", preset: TextPreset.roundedLabel.rawValue, fontSize: 12, rect: rect)))
        #expect(!cover(.arrow(start: .zero, end: CGPoint(x: 9, y: 9), style: .straight)))
    }

    @Test func coverageOfTextLines() {
        let line = CGRect(x: 0, y: 100, width: 600, height: 20)
        // Bar over one word of a long line.
        #expect(RedactionCoverage.coversText(CGRect(x: 200, y: 96, width: 80, height: 28), lines: [line]))
        // Bar over the whole line.
        #expect(RedactionCoverage.coversText(CGRect(x: -5, y: 95, width: 610, height: 30), lines: [line]))
        // A box in empty space, and a big panel that only grazes the line.
        #expect(!RedactionCoverage.coversText(CGRect(x: 0, y: 300, width: 100, height: 50), lines: [line]))
        #expect(!RedactionCoverage.coversText(CGRect(x: 0, y: 115, width: 400, height: 300), lines: [line]))
    }

    @Test func automaticFlagResolvesFromDetectedText() async throws {
        let base = try EffectsFixtures.textImage(RedactionTests.text)
        let lines = try await TextLineDetector().lines(in: base)
        #expect(!lines.isEmpty)
        let overText = Annotation(style: Self.black, kind: .rectangle(rect: Self.secret, filled: true, cornerRadius: 0))
        let offText = Annotation(style: Self.black, kind: .rectangle(rect: CGRect(x: 700, y: 0, width: 50, height: 8),
                                                                    filled: true, cornerRadius: 0))
        let outline = Annotation(kind: .rectangle(rect: Self.secret, filled: false, cornerRadius: 0))
        let document = document(for: base, [overText, offText, outline])

        #expect(document.unmarkedOpaqueCovers(textLines: lines).map(\.id) == [offText.id])
        let resolved = document.resolvingRedactions(textLines: lines)
        #expect(resolved.annotations.map(\.redaction) == [true, nil, nil])
        #expect(ProjectFile.containsRedactions(resolved))
        #expect(!ProjectFile.containsRedactions(document))
    }

    @Test func redactionFlagIsOmittedWhenAutomaticAndRoundTrips() throws {
        let auto = Annotation(kind: .ellipse(rect: Self.secret))
        let json = try #require(String(bytes: JSONEncoder().encode(auto), encoding: .utf8))
        #expect(!json.contains("redaction"))
        let marked = Annotation(kind: .ellipse(rect: Self.secret), redaction: false)
        let decoded = try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(marked))
        #expect(decoded.redaction == false)
    }
}

import CoreGraphics
import Foundation
@testable import ScreenCapKit
import Testing

@Suite("Document coding")
struct DocumentCodingTests {
    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    @Test(arguments: DocumentFixtures.everyKind)
    func annotationKindRoundTrips(kind: Annotation.Kind) throws {
        let annotation = Annotation(
            zIndex: 4,
            style: Annotation.Style(strokeColor: .white, strokeWidth: 3, fillColor: .black,
                                    shadow: Document.Shadow(), opacity: 0.8),
            kind: kind
        )
        #expect(try roundTrip(annotation) == annotation)
    }

    @Test func fullDocumentRoundTrips() throws {
        let gradient = Document.BackgroundFill.linearGradient(
            stops: [.init(color: .red, location: 0), .init(color: .white, location: 1)], angle: 45
        )
        for fill in [gradient, .solid(color: .black), .bundled(name: "dune"), .customImage(layerName: "bg")] {
            let document = Document(
                baseImage: DocumentFixtures.base,
                canvasSize: CGSize(width: 528, height: 428),
                background: Document.Background(fill: fill, alignment: .bottomRight),
                annotations: DocumentFixtures.everyKind.map { Annotation(kind: $0) }
            )
            let decoded = try roundTrip(document)
            #expect(decoded == document)
            #expect(decoded.schemaVersion == 1)
        }
    }

    @Test func canvasDefaultsToBaseImageSize() {
        let document = Document(baseImage: DocumentFixtures.base)
        #expect(document.canvasSize == CGSize(width: 400, height: 300))
    }

    @Test func rejectsNewerSchemaVersion() throws {
        var json = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(Document(baseImage: DocumentFixtures.base)))
                as? [String: Any]
        )
        json["schemaVersion"] = 2
        // A newer file may contain kinds we don't know; the version check must win.
        json["annotations"] = [["kind": ["hologram": [:]]]]
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: ProjectFileError.unsupportedSchemaVersion(found: 2, supported: 1)) {
            try ProjectFile.decodeDocument(data)
        }
    }

    @Test func rejectsZeroSchemaVersion() throws {
        var json = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(Document(baseImage: DocumentFixtures.base)))
                as? [String: Any]
        )
        json["schemaVersion"] = 0
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: ProjectFileError.unsupportedSchemaVersion(found: 0, supported: 1)) {
            try ProjectFile.decodeDocument(data)
        }
    }

    @Test func documentedExampleDecodes() throws {
        // Keep in sync with the example in docs/file-format.md.
        let root = URL(fileURLWithPath: #filePath)
        let docURL = (0..<6).reduce(root) { url, _ in url.deletingLastPathComponent() }
            .appendingPathComponent("docs/file-format.md")
        let markdown = try String(contentsOf: docURL, encoding: .utf8)
        let start = try #require(markdown.range(of: "```json\n"))
        let end = try #require(markdown.range(of: "\n```", range: start.upperBound..<markdown.endIndex))
        let json = String(markdown[start.upperBound..<end.lowerBound])
        let document = try ProjectFile.decodeDocument(Data(json.utf8))
        #expect(document.annotations.count == 3)
        #expect(document.baseImage.pixelWidth == 2880)
    }
}

@Suite("Background edge padding coding")
struct BackgroundEdgePaddingCodingTests {
    @Test func edgePaddingRoundTripsAndOldFilesDecodeAsUniform() throws {
        var background = Document.Background(fill: .solid(color: .black), padding: 20)
        background.edgePadding = EffectsInsets(top: 20, left: 30, bottom: 60, right: 30)
        let decoded = try JSONDecoder().decode(Document.Background.self, from: JSONEncoder().encode(background))
        #expect(decoded == background)
        #expect(decoded.resolvedPadding == EffectsInsets(top: 20, left: 30, bottom: 60, right: 30))

        // A file written before edgePadding existed has no key and falls back to `padding`.
        background.edgePadding = nil
        let json = try JSONEncoder().encode(background)
        #expect(String(bytes: json, encoding: .utf8)?.contains("edgePadding") == false)
        let old = try JSONDecoder().decode(Document.Background.self, from: json)
        #expect(old.edgePadding == nil)
        #expect(old.resolvedPadding == EffectsInsets(all: 20))
    }
}

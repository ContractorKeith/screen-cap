import CoreGraphics
import Foundation
@testable import ScreenCapKit
import Testing

// Serialized: the redaction test runs Vision, and concurrent Vision + Core Image requests deadlock on
// GitHub's paravirtualized macOS runners.
@Suite("ProjectFile", .serialized)
struct ProjectFileTests {
    private func tempPackageURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenCapKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Capture.screencap", isDirectory: true)
    }

    private func sampleDocument() -> Document {
        var doc = Document(
            baseImage: Document.BaseImage(pixelWidth: 640, pixelHeight: 480, scale: 2),
            canvasSize: CGSize(width: 768, height: 608),
            background: Document.Background(fill: .customImage(layerName: "wallpaper"))
        )
        for kind in DocumentFixtures.everyKind { doc.add(Annotation(kind: kind)) }
        return doc
    }

    @Test func writeThenReadRoundTrips() throws {
        let url = try tempPackageURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let document = sampleDocument()
        let base = DocumentFixtures.image(width: 640, height: 480)
        let layers = [
            "pasted-1": DocumentFixtures.image(width: 64, height: 32, red: 0, green: 1),
            "wallpaper": DocumentFixtures.image(width: 20, height: 10, red: 0, blue: 1)
        ]
        try ProjectFile.write(document, baseImage: base, layers: layers, bakeRedactions: false, to: url)

        for file in ["document.json", "base.png", "preview.png", "layers/pasted-1.png", "layers/wallpaper.png"] {
            #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent(file).path), "\(file)")
        }

        let contents = try ProjectFile.read(from: url)
        #expect(contents.document == document)
        #expect(contents.baseImage.width == 640)
        #expect(contents.baseImage.height == 480)
        #expect(contents.layers["pasted-1"]?.width == 64)
        #expect(contents.layers["pasted-1"]?.height == 32)
        #expect(contents.layers["wallpaper"]?.width == 20)
        let preview = try #require(contents.preview)
        #expect(max(preview.width, preview.height) == ProjectFile.previewMaxPixels)
    }

    @Test func overwriteReplacesExistingPackage() throws {
        let url = try tempPackageURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let base = DocumentFixtures.image(width: 8, height: 8)
        let first = Document(baseImage: Document.BaseImage(pixelWidth: 8, pixelHeight: 8, scale: 1))
        try ProjectFile.write(first, baseImage: base,
                              layers: ["old": DocumentFixtures.image(width: 2, height: 2)], to: url)
        var second = first
        second.add(DocumentFixtures.counter(1))
        try ProjectFile.write(second, baseImage: base, to: url)

        let contents = try ProjectFile.read(from: url)
        #expect(contents.document == second)
        #expect(contents.layers.isEmpty)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(siblings == ["Capture.screencap"])
    }

    @Test func readRejectsNewerSchema() throws {
        let url = try tempPackageURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let base = DocumentFixtures.image(width: 8, height: 8)
        var document = Document(baseImage: Document.BaseImage(pixelWidth: 8, pixelHeight: 8, scale: 1))
        document.schemaVersion = 99
        try ProjectFile.write(document, baseImage: base, to: url)
        #expect(throws: ProjectFileError.unsupportedSchemaVersion(found: 99, supported: 1)) {
            try ProjectFile.read(from: url)
        }
    }

    @Test func writeRejectsMissingOrInvalidLayers() throws {
        let url = try tempPackageURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let base = DocumentFixtures.image(width: 8, height: 8)
        var document = Document(baseImage: Document.BaseImage(pixelWidth: 8, pixelHeight: 8, scale: 1))
        document.add(Annotation(kind: .imageLayer(layerName: "gone", rect: .zero)))
        #expect(throws: ProjectFileError.missingLayer("gone")) {
            try ProjectFile.write(document, baseImage: base, to: url)
        }
        #expect(throws: ProjectFileError.invalidLayerName("../evil")) {
            try ProjectFile.write(document, baseImage: base, layers: ["../evil": base], to: url)
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func readMissingPackageThrows() {
        let url = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString).screencap")
        #expect(throws: ProjectFileError.missingFile("document.json")) {
            try ProjectFile.read(from: url)
        }
    }

    // MARK: - Redactions are baked (#40)

    @Test func savedRedactionDoesNotContainOriginalPixels() throws {
        let url = try tempPackageURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let base = try EffectsFixtures.textImage(RedactionTests.text)
        let secret = RedactionTests.textRect
        var document = Document(baseImage: Document.BaseImage(pixelWidth: base.width, pixelHeight: base.height,
                                                              scale: 1))
        // Beneath and overlapping the blur: baked. Text holds data that must not survive in JSON.
        document.add(Annotation(kind: .text(string: "hunter2", preset: 1, fontSize: 20,
                                            rect: CGRect(x: 30, y: 20, width: 120, height: 30))))
        document.add(Annotation(kind: .blur(rect: secret, mode: .secure, radius: 12)))
        document.add(Annotation(kind: .pixelate(rect: CGRect(x: 600, y: 10, width: 100, height: 60),
                                                blockSize: 12, randomize: true)))
        // Above the redactions: stays editable.
        let arrow = Annotation(kind: .arrow(start: CGPoint(x: 10, y: 95), end: CGPoint(x: 700, y: 95),
                                            style: .straight))
        document.add(arrow)
        try ProjectFile.write(document, baseImage: base, to: url)

        let contents = try ProjectFile.read(from: url)
        #expect(contents.document.annotations.map(\.id) == [arrow.id])
        let json = try String(contentsOf: url.appendingPathComponent(ProjectFile.documentFileName), encoding: .utf8)
        #expect(!json.contains("hunter2"))
        #expect(!json.contains("blur") && !json.contains("pixelate"))

        // The secret's pixels were replaced, the rest of the capture kept exactly, and OCR finds nothing.
        let saved = contents.baseImage
        #expect(saved.width == base.width && saved.height == base.height)
        var changed = 0
        for y in stride(from: Int(secret.minY), to: Int(secret.maxY), by: 2) {
            for x in stride(from: Int(secret.minX), to: Int(secret.maxX), by: 2)
            where try EffectsFixtures.pixel(saved, x: x, y: y) != EffectsFixtures.pixel(base, x: x, y: y) {
                changed += 1
            }
        }
        #expect(changed > Int(secret.width * secret.height) / 4 / 4)
        for y in [2, 97] {
            #expect(try EffectsFixtures.pixel(saved, x: 300, y: y) == EffectsFixtures.pixel(base, x: 300, y: y))
        }
        #expect(try RedactionTests.leakedWords(in: saved).isEmpty)
        #expect(try RedactionTests.leakedWords(in: base).count >= 2)
    }

    @Test func layerBeneathRedactionIsBakedAndDropped() throws {
        let url = try tempPackageURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let base = DocumentFixtures.image(width: 200, height: 100)
        var document = Document(baseImage: Document.BaseImage(pixelWidth: 200, pixelHeight: 100, scale: 1))
        document.add(Annotation(kind: .imageLayer(layerName: "hidden",
                                                  rect: CGRect(x: 10, y: 10, width: 40, height: 40))))
        document.add(Annotation(kind: .imageLayer(layerName: "kept",
                                                  rect: CGRect(x: 150, y: 10, width: 40, height: 40))))
        document.add(Annotation(kind: .pixelate(rect: CGRect(x: 0, y: 0, width: 60, height: 60),
                                                blockSize: 12, randomize: true)))
        let layers = ["hidden": DocumentFixtures.image(width: 4, height: 4, red: 0, green: 1),
                      "kept": DocumentFixtures.image(width: 4, height: 4, red: 0, blue: 1)]
        #expect(ProjectFile.containsRedactions(document))
        try ProjectFile.write(document, baseImage: base, layers: layers, to: url)

        let contents = try ProjectFile.read(from: url)
        #expect(Set(contents.layers.keys) == ["kept"])
        #expect(!FileManager.default.fileExists(atPath: url.appendingPathComponent("layers/hidden.png").path))
        #expect(contents.document.referencedLayerNames == ["kept"])
    }

    @Test func documentWithoutRedactionsIsUnchanged() throws {
        let base = DocumentFixtures.image(width: 8, height: 8)
        var document = Document(baseImage: Document.BaseImage(pixelWidth: 8, pixelHeight: 8, scale: 1))
        document.add(DocumentFixtures.counter(1))
        #expect(!ProjectFile.containsRedactions(document))
        let baked = try ProjectFile.bakingRedactions(document, baseImage: base, layers: [:])
        #expect(baked.document == document)
        #expect(baked.baseImage === base)
    }
}

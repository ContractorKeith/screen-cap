import CoreGraphics
import Foundation
@testable import ScreenCapKit
import Testing

@Suite("ProjectFile")
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
        try ProjectFile.write(document, baseImage: base, layers: layers, to: url)

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
}

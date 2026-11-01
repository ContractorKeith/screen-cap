import CoreGraphics
import Foundation
@testable import ScreenCapKit
import Testing

@Suite("Document numeric validation")
struct DocumentValidationTests {
    private let invalidPositive = ["NaN", "Infinity", "-Infinity", "-1", "0", "1e100"]

    private func json(canvas: String = "[20,20]", base: String = "20", scale: String = "2",
                      background: String = "null", annotations: String = "[]") -> Data {
        Data("""
        {"schemaVersion":1,"baseImage":{"pixelWidth":\(base),"pixelHeight":20,"scale":\(scale)},
         "canvasSize":\(canvas),"background":\(background),"annotations":\(annotations)}
        """.utf8)
    }

    /// Non-finite values are strings because JSON has no NaN or infinity literals.
    private func token(_ value: String) -> String {
        ["NaN", "Infinity", "-Infinity"].contains(value) ? "\"\(value)\"" : value
    }

    private func reject(_ data: Data, field: String) throws {
        let error = ProjectFileError.invalidGeometry(field)
        #expect(throws: error) { try ProjectFile.decodeDocument(data) }
        // Also exercise actual non-finite Doubles, rather than just JSON type errors.
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        #expect(throws: error) { try decoder.decode(Document.self, from: data) }
        #expect(error.localizedDescription == "This project’s \(field) is invalid.")
    }

    @Test func rejectsInvalidCanvasDimensions() throws {
        for value in invalidPositive {
            for canvas in ["[\(token(value)),20]", "[20,\(token(value))]"] {
                try reject(json(canvas: canvas), field: "canvas size")
            }
        }
        try reject(json(canvas: "[20000,20000]"), field: "canvas size")
    }

    @Test func rejectsInvalidBaseDimensionsAndScale() throws {
        for value in invalidPositive {
            try reject(json(base: token(value)), field: "base image size or scale")
            try reject(json(scale: token(value)), field: "base image size or scale")
        }
        try reject(json(scale: "1e-100"), field: "base image size or scale")
    }

    @Test func rejectsInvalidPaddingOnEveryEdge() throws {
        for value in invalidPositive where value != "0" {
            for edge in ["top", "left", "bottom", "right", "padding"] {
                var fields = ["top": "0", "left": "0", "bottom": "0", "right": "0"]
                fields[edge] = token(value)
                let edges = ["top", "left", "bottom", "right"].map { "\"\($0)\":\(fields[$0]!)" }
                    .joined(separator: ",")
                let background = """
                {"fill":{"solid":{"color":{"red":0,"green":0,"blue":0,"alpha":1}}},
                 "padding":\(fields["padding"] ?? "0"),"cornerRadius":0,"alignment":"center",
                 "edgePadding":{\(edges)}}
                """
                try reject(json(background: background), field: "background geometry")
            }
        }
    }

    @Test func rejectsInvalidAnnotationGeometryAndEffectSizes() throws {
        for value in invalidPositive {
            let scalar = token(value)
            var kinds = ["\"pixelate\":{\"rect\":[[0,0],[10,10]],\"blockSize\":\(scalar),\"randomize\":false}"]
            if value != "0" {
                kinds += [
                    "\"blur\":{\"rect\":[[0,0],[10,10]],\"mode\":\"secure\",\"radius\":\(scalar)}",
                    "\"ellipse\":{\"rect\":[[0,0],[\(scalar),10]]}"
                ]
            }
            if value != "0" && value != "-1" {
                kinds.append("\"line\":{\"start\":[\(scalar),0],\"end\":[1,1]}")
            }
            for kind in kinds {
                let annotations = """
                [{"id":"AFBADBDD-CC0B-4873-9350-A1469531CDD9","zIndex":0,
                  "style":{"strokeColor":{"red":0,"green":0,"blue":0,"alpha":1},"strokeWidth":1,"opacity":1},
                  "kind":{\(kind)}}]
                """
                try reject(json(annotations: annotations), field: "annotation geometry")
            }
        }
    }

    @Test func acceptsBoundarySizes() throws {
        #expect(try ProjectFile.decodeDocument(json(canvas: "[65536,20]", scale: "0.01")).canvasSize.width == 65536)
        try reject(json(canvas: "[65537,20]"), field: "canvas size")
    }

    @Test func acceptsZeroPaddingAndNegativeCoordinates() throws {
        let document = Document(baseImage: .init(pixelWidth: 20, pixelHeight: 20, scale: 2),
                                background: .init(fill: .solid(color: .white), padding: 0,
                                                  cornerRadius: 0, edgePadding: EffectsInsets(all: 0)),
                                annotations: [.init(kind: .line(start: CGPoint(x: -10, y: -10), end: .zero)),
                                              .init(kind: .ellipse(rect: .zero))])
        #expect(try ProjectFile.decodeDocument(JSONEncoder().encode(document)) == document)
    }

    @Test func malformedPackageFailsBeforeLoadingImages() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".screencap")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        try json(canvas: "[1e100,20]").write(to: url.appendingPathComponent("document.json"))
        #expect(throws: ProjectFileError.invalidGeometry("canvas size")) { try ProjectFile.read(from: url) }
        #expect(try ProjectFile.decodeDocument(json()).canvasSize == CGSize(width: 20, height: 20))
    }
}

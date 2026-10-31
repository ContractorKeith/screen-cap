import CoreGraphics
import Foundation
@testable import ScreenCapKit
import Testing
import Vision

/// Runs real Vision requests against images rendered in code.
@Suite("Vision recognition", .serialized)
struct VisionRecognitionTests {
    struct OCRCase: Sendable, CustomStringConvertible {
        let name: String
        let text: String
        let font: String
        let size: CGFloat
        let languages: [String]?
        let ignoresWhitespace: Bool
        let minimumAccuracy: Double
        var usesLanguageCorrection = true
        var description: String { name }
    }

    static let ocrCases: [OCRCase] = [
        OCRCase(
            name: "English",
            text: """
            The quick brown fox jumps over the lazy dog while the busy editor captures every \
            window on the screen. Text recognition runs entirely on this Mac, so nothing leaves \
            the device and results appear in a fraction of a second.
            """,
            font: "Helvetica", size: 16, languages: nil, ignoresWhitespace: false, minimumAccuracy: 0.98
        ),
        OCRCase(
            name: "German",
            text: """
            Fünf große Bären überqueren die Straße und grüßen höflich. Die Größe der Schrift \
            spielt keine Rolle, solange die Umlaute ä, ö und ü sowie das ß korrekt erkannt werden.
            """,
            font: "Helvetica", size: 16, languages: nil, ignoresWhitespace: false, minimumAccuracy: 0.98
        ),
        OCRCase(
            name: "Japanese",
            text: """
            画面のスクリーンショットを撮影して、文字を認識します。\
            この処理はすべて端末の中で行われるので、安全です。\
            日本語の文章も正しく読み取れるか確認します。
            """,
            font: "Hiragino Sans", size: 18, languages: ["ja-JP", "en-US"], ignoresWhitespace: true,
            minimumAccuracy: 0.98
        ),
        OCRCase(
            name: "Code",
            text: """
            func greet(name: String) -> String {
                let count = name.count + 42
                return "Hello, \\(name)! [\\(count)]"
            }
            """,
            // Vision's model differs per macOS release: 99% on macOS 26, 94% on the macOS 15 CI runner.
            font: "Menlo", size: 16, languages: nil, ignoresWhitespace: false, minimumAccuracy: 0.92,
            // Code isn't prose: dictionary correction rewrites identifiers and punctuation.
            usesLanguageCorrection: false
        )
    ]

    @Test(arguments: ocrCases)
    func ocrFixtureReachesCharacterAccuracy(_ fixture: OCRCase) async throws {
        let image = VisionFixtures.paragraph(fixture.text, font: fixture.font, size: fixture.size)
        let result = try await TextRecognizer().recognize(
            in: image, languages: fixture.languages, level: .accurate,
            usesLanguageCorrection: fixture.usesLanguageCorrection
        )
        #expect(!result.isEmpty)
        #expect(result.lines.allSatisfy { $0.confidence > 0 && $0.boundingBox.width > 0 })

        let normalize = fixture.ignoresWhitespace ? TextAccuracy.removingWhitespace : TextAccuracy.collapsingWhitespace
        let expected = normalize(fixture.text)
        let actual = normalize(result.text(keepLineBreaks: false))
        let accuracy = TextAccuracy.characterAccuracy(expected: expected, actual: actual)
        print("OCR \(fixture.name): \(String(format: "%.2f", accuracy * 100))% -> \(actual)")
        #expect(accuracy >= fixture.minimumAccuracy, "\(fixture.name) OCR: \(actual)")
    }

    @Test func recognizedBoxesAreInsideImageWithTopLeftOrigin() async throws {
        let rendered = VisionFixtures.lines(["Top line", "Bottom line"], font: "Helvetica", size: 24, spacing: 60)
        let result = try await TextRecognizer().recognize(in: rendered.image)
        let bounds = CGRect(x: 0, y: 0, width: rendered.image.width, height: rendered.image.height)
        #expect(result.lines.count == 2)
        #expect(result.lines.allSatisfy { bounds.insetBy(dx: -1, dy: -1).contains($0.boundingBox) })
        let top = try #require(result.lines.first { $0.string.contains("Top") })
        let bottom = try #require(result.lines.first { $0.string.contains("Bottom") })
        #expect(top.boundingBox.midY < bottom.boundingBox.midY)
        #expect(result.text(keepLineBreaks: true) == "Top line\nBottom line")
    }

    @Test func supportedLanguagesIncludeFixtureLanguages() async throws {
        let languages = try await TextRecognizer().supportedLanguages()
        for code in ["en-US", "de-DE", "ja-JP"] {
            #expect(languages.contains(code))
        }
    }

    @Test func qrCodeReadsBackPayloadAndURL() async throws {
        let payload = "https://example.com/test"
        let image = try VisionFixtures.qrCode(payload)
        let codes = try await BarcodeReader().read(in: image)
        let code = try #require(codes.first)
        #expect(codes.count == 1)
        #expect(code.payload == payload)
        #expect(code.symbology == VNBarcodeSymbology.qr.rawValue)
        #expect(code.url == URL(string: payload))
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        #expect(code.boundingBox.width > 0 && bounds.insetBy(dx: -1, dy: -1).contains(code.boundingBox))
    }

    @Test func blankImageHasNoText() async throws {
        let image = VisionFixtures.paragraph(" ", font: "Helvetica", size: 16)
        #expect(try await TextRecognizer().recognize(in: image).isEmpty)
        #expect(try await BarcodeReader().read(in: image).isEmpty)
    }

    @Test func textLineDetectorFindsLinesAndSnapsToMiddle() async throws {
        let rendered = VisionFixtures.lines(
            ["Highlight the first line", "Then the middle line here", "And finally the last one"],
            font: "Helvetica", size: 22, spacing: 56
        )
        let lines = try await TextLineDetector().lines(in: rendered.image)
        #expect(lines.count == 3)
        #expect(lines == lines.sorted { $0.minY < $1.minY })

        // Each detected box sits on the band where that line was drawn.
        for (box, band) in zip(lines, rendered.bands) {
            #expect(band.contains(box.midY), "box \(box) not on band \(band)")
        }

        // A highlighter stroke through the middle of line 2, as the user would drag it.
        let middle = rendered.bands[1]
        let stroke = CGRect(x: 60, y: (middle.lowerBound + middle.upperBound) / 2 - 6, width: 300, height: 12)
        #expect(TextLineDetector.snapHeight(for: stroke, lines: lines) == lines[1])
    }
}

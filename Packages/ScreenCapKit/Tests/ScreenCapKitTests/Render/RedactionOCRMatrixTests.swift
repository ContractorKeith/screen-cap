import CoreGraphics
import CoreText
import Foundation
import ImageIO
@testable import ScreenCapKit
import Testing

// PLAN §5.6 at every setting the inspector allows: secure blur and randomized pixelate, drawn
// tightly around text of 12–72 px, exported as PNG at 1x and 2x through the real Renderer +
// Exporter path, must leave Vision nothing of 3+ characters to read.
// Serialized: concurrent Vision + Core Image requests deadlock on GitHub's paravirtualized macOS runners.
@Suite("Redaction OCR matrix", .serialized)
struct RedactionOCRMatrixTests {
    static let text = "Secret 4829 1173 payroll"
    static let words = Set(text.lowercased().split(separator: " ").map(String.init))
    static let textSizes: [CGFloat] = [12, 16, 24, 32, 48, 72]
    static let scales: [Double] = [1, 2]

    /// Inspector minimums and defaults (InspectorView sliders, ToolOptions); 2 and 4 cover
    /// documents saved before the minimums were raised.
    static func configs(_ rect: CGRect) -> [(name: String, kind: Annotation.Kind)] {
        [
            ("secure r=2", .blur(rect: rect, mode: .secure, radius: 2)),
            ("secure r=4", .blur(rect: rect, mode: .secure, radius: 4)),
            ("secure r=12", .blur(rect: rect, mode: .secure, radius: 12)),
            ("pixelate 4 random", .pixelate(rect: rect, blockSize: 4, randomize: true)),
            ("pixelate 8 random", .pixelate(rect: rect, blockSize: 8, randomize: true)),
            ("pixelate 12 random", .pixelate(rect: rect, blockSize: 12, randomize: true))
        ]
    }

    /// Black text on white, plus the tight rect (2 px margin) around its glyphs, top-left pixels.
    static func fixture(fontSize: CGFloat) throws -> (image: CGImage, textRect: CGRect) {
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): RGBAColor.black.cgColor
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let glyphs = CTLineGetImageBounds(line, nil)
        let margin = fontSize
        let width = Int((glyphs.width + margin * 2).rounded(.up))
        let height = Int((glyphs.height + margin * 2).rounded(.up))
        let origin = CGPoint(x: margin - glyphs.minX, y: margin - glyphs.minY)
        let image = try EffectsFixtures.image(width: width, height: height, fill: .white) { context in
            context.textPosition = origin
            CTLineDraw(line, context)
        }
        // Glyph box in CG space is (margin, margin, w, h); flip to top-left.
        let rect = CGRect(x: margin, y: CGFloat(height) - margin - glyphs.height,
                          width: glyphs.width, height: glyphs.height).insetBy(dx: -2, dy: -2)
        return (image, rect)
    }

    /// Renders `kinds` over `image`, exports a PNG at `scale` and decodes it again.
    static func exportedPNG(_ image: CGImage, kinds: [Annotation.Kind], scale: Double) throws -> CGImage {
        let document = Document(
            baseImage: Document.BaseImage(pixelWidth: image.width, pixelHeight: image.height, scale: 1),
            annotations: kinds.enumerated().map { Annotation(zIndex: $0.offset, kind: $0.element) }
        )
        let rendered = try Renderer().image(for: document, baseImage: image, options: RenderOptions(scale: scale))
        let data = try Exporter(image: rendered, format: .png, scale: scale).data()
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// Recognized tokens of 3+ characters that match, or are contained in, an original word.
    static func leakedWords(in image: CGImage) throws -> [String] {
        let recognized = try EffectsFixtures.recognizedText(in: image)
        let tokens = recognized.flatMap { string in
            string.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        }
        let exact = tokens.filter { $0.count >= 3 && words.contains($0) }
        let joined = recognized.joined(separator: " ").lowercased()
        let partial = tokens.filter { token in
            token.count >= 3 && words.contains { $0 != token && $0.contains(token) }
        }
        return exact + partial + words.filter { joined.contains($0) }
    }

    @Test(arguments: textSizes)
    func unredactedExportIsReadable(fontSize: CGFloat) throws {
        // Guards the matrix: without redaction Vision reads the fixture at every size.
        let fixture = try Self.fixture(fontSize: fontSize)
        let exported = try Self.exportedPNG(fixture.image, kinds: [], scale: 1)
        #expect(try Self.leakedWords(in: exported).count >= 2, "\(fontSize) px")
    }

    /// The weakest setting of each mode (#140): the full matrix runs in the slow tier.
    static func minimumConfigs(_ rect: CGRect) -> [(name: String, kind: Annotation.Kind)] {
        configs(rect).filter { $0.name == "secure r=2" || $0.name == "pixelate 4 random" }
    }

    // PLAN §5.6 at the weakest settings, smallest and largest text, 1x and 2x (#140; full matrix in
    // `RedactionOCRMatrixSlowTests`).
    @Test(arguments: [CGFloat(12), 72])
    func secureRedactionDefeatsOCR(fontSize: CGFloat) throws {
        try Self.expectNothingLeaks(fontSize: fontSize, configs: Self.minimumConfigs)
    }

    static func expectNothingLeaks(fontSize: CGFloat,
                                   configs: (CGRect) -> [(name: String, kind: Annotation.Kind)]) throws {
        let fixture = try Self.fixture(fontSize: fontSize)
        for config in configs(fixture.textRect) {
            for scale in Self.scales {
                let exported = try Self.exportedPNG(fixture.image, kinds: [config.kind], scale: scale)
                let leaked = try Self.leakedWords(in: exported)
                #expect(leaked.isEmpty, "\(fontSize) px, \(config.name), \(scale)x: \(leaked)")
            }
        }
    }

    @Test func secureBlockScalesWithTheRect() {
        let size = CGSize(width: 2000, height: 2000)
        // Floor for small rects, share of the shorter side for big ones, request when larger.
        #expect(Redaction.secureBlockSize(requested: 2, rect: CGRect(x: 0, y: 0, width: 100, height: 10),
                                          imageSize: size) == Redaction.minimumSecureBlock)
        #expect(Redaction.secureBlockSize(requested: 2, rect: CGRect(x: 0, y: 0, width: 900, height: 100),
                                          imageSize: size) == 40)
        #expect(Redaction.secureBlockSize(requested: 64, rect: CGRect(x: 0, y: 0, width: 900, height: 100),
                                          imageSize: size) == 64)
        // A 2x export doubles the rect, so the block doubles too: bigger exports aren't weaker.
        #expect(Redaction.secureBlockSize(requested: 4, rect: CGRect(x: 0, y: 0, width: 1800, height: 200),
                                          imageSize: size) == 80)
    }
}

/// Every inspector setting at every text size (PLAN §5.6, #140). Run with `make test-slow`.
@Suite("Redaction OCR matrix, every setting", .serialized, .tags(.slow))
struct RedactionOCRMatrixSlowTests {
    @Test(arguments: RedactionOCRMatrixTests.textSizes)
    func secureRedactionDefeatsOCR(fontSize: CGFloat) throws {
        try RedactionOCRMatrixTests.expectNothingLeaks(fontSize: fontSize, configs: RedactionOCRMatrixTests.configs)
    }
}

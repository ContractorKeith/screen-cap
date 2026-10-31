import CoreGraphics
import Foundation
@testable import ScreenCapKit
import Testing

// The default renderer applies the Effects redactions end to end.
// Serialized: concurrent Vision + Core Image requests deadlock on GitHub's paravirtualized macOS runners.
@Suite("Renderer redaction", .serialized)
struct RendererRedactionTests {
    static let text = RedactionTests.text
    static let blurRect = CGRect(x: 10, y: 10, width: 200, height: 80)
    static let pixelateRect = CGRect(x: 220, y: 10, width: 200, height: 80)
    /// Spotlight keeps x < 640 bright and dims the strip to its right.
    static let spotlightRect = CGRect(x: 0, y: 0, width: 640, height: 100)

    static func document(_ kinds: [Annotation.Kind], for image: CGImage) -> Document {
        Document(baseImage: Document.BaseImage(pixelWidth: image.width, pixelHeight: image.height, scale: 1),
                 annotations: kinds.enumerated().map { Annotation(zIndex: $0.offset, kind: $0.element) })
    }

    /// Pixels in `rect` (output pixels) that differ between `lhs` and `rhs`.
    static func changedCount(_ lhs: RenderedPixels, _ rhs: RenderedPixels, in rect: CGRect) -> Int {
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) where lhs[x, y] != rhs[x, y] {
                count += 1
            }
        }
        return count
    }

    static func scaled(_ rect: CGRect, _ scale: Double) -> CGRect {
        CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }

    @Test(arguments: [1.0, 2.0])
    func blurPixelateAndSpotlightChangeOnlyTheirRegions(scale: Double) throws {
        let image = try EffectsFixtures.textImage(Self.text)
        let document = Self.document([
            .blur(rect: Self.blurRect, mode: .secure, radius: 8),
            .pixelate(rect: Self.pixelateRect, blockSize: 12, randomize: true),
            .spotlight(shapes: [.rect(rect: Self.spotlightRect)])
        ], for: image)
        let options = RenderOptions(scale: scale)
        let reference = RenderedPixels(try Renderer(redaction: NoOpRedactionRenderer())
            .image(for: document, baseImage: image, options: options))
        let redacted = RenderedPixels(try Renderer(redaction: EffectsRedactionRenderer(seed: 7))
            .image(for: document, baseImage: image, options: options))

        // Blur and pixelate rewrite most of their rects (white margins can survive a blur).
        for rect in [Self.blurRect, Self.pixelateRect] {
            let area = Self.scaled(rect, scale)
            #expect(Self.changedCount(reference, redacted, in: area) > Int(area.width * area.height) / 4)
        }
        // Inside the spotlight but outside both redactions: untouched.
        let gaps = [CGRect(x: 0, y: 0, width: 640, height: 10), CGRect(x: 0, y: 90, width: 640, height: 10),
                    CGRect(x: 0, y: 10, width: 10, height: 80), CGRect(x: 210, y: 10, width: 10, height: 80),
                    CGRect(x: 420, y: 10, width: 220, height: 80)]
        for gap in gaps {
            #expect(Self.changedCount(reference, redacted, in: Self.scaled(gap, scale)) == 0)
        }
        // Outside the spotlight: every pixel dimmed.
        let outside = Self.scaled(CGRect(x: 640, y: 0, width: 120, height: 100), scale)
        #expect(Self.changedCount(reference, redacted, in: outside) == Int(outside.width * outside.height))
        let dimmed = redacted[Int(outside.midX), Int(outside.midY)]
        #expect(abs(dimmed.red - 128) <= 3 && dimmed.alpha == 255)
    }

    @Test func sameSeedRendersIdentically() throws {
        let image = try EffectsFixtures.textImage(Self.text)
        let document = Self.document([.blur(rect: Self.blurRect, mode: .secure, radius: 8)], for: image)
        let renderer = Renderer(redaction: EffectsRedactionRenderer(seed: 3))
        let first = RenderedPixels(try renderer.image(for: document, baseImage: image))
        let second = RenderedPixels(try renderer.image(for: document, baseImage: image))
        #expect(first == second)
    }

    @Test func blurModesMapToEffectsModes() {
        #expect(Redaction.BlurMode(Annotation.BlurMode.secure) == .secure)
        #expect(Redaction.BlurMode(Annotation.BlurMode.smooth) == .smooth)
    }

    // MARK: - PLAN §5.6 through the renderer

    @Test func unredactedRenderIsReadable() throws {
        // Guards the tests below: the render pipeline alone keeps the text readable.
        let image = try EffectsFixtures.textImage(Self.text)
        let rendered = try Renderer().image(for: Self.document([], for: image), baseImage: image)
        #expect(try RedactionTests.leakedWords(in: rendered).count >= 2)
    }

    @Test func secureBlurDefeatsVisionEndToEnd() throws {
        let image = try EffectsFixtures.textImage(Self.text)
        let document = Self.document([.blur(rect: RedactionTests.textRect, mode: .secure, radius: 8)], for: image)
        let rendered = try Renderer().image(for: document, baseImage: image)
        #expect(try RedactionTests.leakedWords(in: rendered).isEmpty)
    }

    @Test func randomizedPixelateDefeatsVisionEndToEnd() throws {
        let image = try EffectsFixtures.textImage(Self.text)
        let document = Self.document([.pixelate(rect: RedactionTests.textRect, blockSize: 14, randomize: true)],
                                     for: image)
        let rendered = try Renderer().image(for: document, baseImage: image)
        #expect(try RedactionTests.leakedWords(in: rendered).isEmpty)
    }
}

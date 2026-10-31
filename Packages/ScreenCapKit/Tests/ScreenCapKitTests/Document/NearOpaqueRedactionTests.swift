import CoreGraphics
import Foundation
@testable import ScreenCapKit
import Testing

// #99: bars that look black but aren't fully opaque count as redactions, and bake solid, so a
// levels stretch (0–20 → 0–255) on the saved base.png recovers nothing. Fixture from the
// 2026-10-31 skeptic pass 3 harness (`redact3`).
// Serialized: Vision requests deadlock when run concurrently on CI runners.
@Suite("Near-opaque redactions", .serialized)
struct NearOpaqueRedactionTests {
    private static let text = RedactionOCRMatrixTests.text
    private static let cover = RedactionTests.textRect

    private static func fixture() throws -> CGImage {
        try EffectsFixtures.textImage(text, width: 760, height: 100, fontSize: 48)
    }

    private static func cases() -> [(name: String, annotation: Annotation)] {
        let bar = Annotation.Kind.rectangle(rect: cover, filled: true, cornerRadius: 0)
        return [
            ("black rect 98%", Annotation(style: .init(fillColor: .black, opacity: 0.98), kind: bar)),
            ("black rect 95%", Annotation(style: .init(fillColor: .black, opacity: 0.95), kind: bar)),
            ("fill alpha 0.97", Annotation(style: .init(fillColor: RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.97)),
                                           kind: bar)),
            ("dark gray highlight", Annotation(kind: .highlight(region: .rect(rect: cover),
                                                                color: RGBAColor(red: 0.05, green: 0.05, blue: 0.05))))
        ]
    }

    private static func document(_ base: CGImage, _ annotation: Annotation) -> Document {
        Document(baseImage: .init(pixelWidth: base.width, pixelHeight: base.height, scale: 1),
                 annotations: [annotation])
    }

    /// Levels: maps 0...20 to 0...255, which brings back text under a near-black bar.
    static func stretched(_ image: CGImage) throws -> CGImage {
        let width = image.width, height = image.height
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        for index in 0..<(width * height) {
            for channel in 0..<3 {
                pixels[index * 4 + channel] = UInt8(min(255, Int(pixels[index * 4 + channel]) * 255 / 20))
            }
        }
        return try #require(context.makeImage())
    }

    @Test func stretchRecoversTextUnderAnUnmarkedNearOpaqueBar() throws {
        let base = try Self.fixture()
        var bar = Self.cases()[0].annotation
        bar.redaction = false
        let render = try Renderer().image(for: Self.document(base, bar), baseImage: base)
        #expect(try !RedactionOCRMatrixTests.leakedWords(in: Self.stretched(render)).isEmpty)
    }

    @Test func nearOpaqueCoversOverTextBakeCleanEvenAfterALevelsStretch() async throws {
        let base = try Self.fixture()
        let lines = try await TextLineDetector().lines(in: base)
        #expect(!lines.isEmpty)
        for (name, annotation) in Self.cases() {
            #expect(annotation.isOpaqueCover, "\(name)")
            #expect(annotation.resolvedRedaction(textLines: lines), "\(name)")
            let document = Self.document(base, annotation)
            #expect(document.unmarkedOpaqueCovers(textLines: lines).isEmpty, "\(name)")

            let resolved = document.resolvingRedactions(textLines: lines)
            let export = try Renderer().image(for: resolved, baseImage: base)
            #expect(try RedactionOCRMatrixTests.leakedWords(in: Self.stretched(export)).isEmpty, "\(name) export")

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("NearOpaque-\(UUID().uuidString).\(ProjectFile.fileExtension)")
            defer { try? FileManager.default.removeItem(at: url) }
            try ProjectFile.write(resolved, baseImage: base, to: url)
            let saved = try ProjectFile.read(from: url)
            #expect(saved.document.annotations.isEmpty, "\(name)")
            #expect(try RedactionOCRMatrixTests.leakedWords(in: Self.stretched(saved.baseImage)).isEmpty,
                    "\(name) base.png")
        }
    }

    @Test func nearOpaqueCoverOffTextIsListedInTheSaveWarning() {
        let swatch = Annotation(style: .init(fillColor: .black, opacity: 0.95),
                                kind: .rectangle(rect: CGRect(x: 0, y: 0, width: 8, height: 8), filled: true,
                                                 cornerRadius: 0))
        let document = Document(baseImage: .init(pixelWidth: 100, pixelHeight: 100, scale: 1), annotations: [swatch])
        #expect(document.unmarkedOpaqueCovers(textLines: []).map(\.id) == [swatch.id])
    }

    @Test func coverThresholds() {
        let rect = CGRect(x: 0, y: 0, width: 50, height: 20)
        let bar = Annotation.Kind.rectangle(rect: rect, filled: true, cornerRadius: 0)
        #expect(Annotation(style: .init(fillColor: .black, opacity: 0.9), kind: bar).isOpaqueCover)
        #expect(!Annotation(style: .init(fillColor: .black, opacity: 0.85), kind: bar).isOpaqueCover)
        // Opacity and fill alpha combine.
        #expect(!Annotation(style: .init(fillColor: RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.94), opacity: 0.94),
                            kind: bar).isOpaqueCover)
        let dark = RGBAColor(red: 0.15, green: 0.1, blue: 0.2)
        #expect(Annotation(kind: .highlight(region: .rect(rect: rect), color: dark)).isOpaqueCover)
        let midGray = RGBAColor(red: 0.4, green: 0.4, blue: 0.4)
        #expect(!Annotation(kind: .highlight(region: .rect(rect: rect), color: midGray)).isOpaqueCover)
        #expect(!Annotation(kind: .highlight(region: .rect(rect: rect), color: .highlightYellow)).isOpaqueCover)
    }

    @Test func solidCoverOnlyChangesShapesUsedAsRedactions() {
        let rect = CGRect(x: 0, y: 0, width: 50, height: 20)
        let faint = Annotation(style: .init(fillColor: .black, opacity: 0.5),
                               kind: .rectangle(rect: rect, filled: true, cornerRadius: 0))
        #expect(faint.solidCover == faint)
        var marked = faint
        marked.redaction = true
        #expect(marked.solidCover.style.opacity == 1)
        #expect(marked.solidCover.isOpaqueCover)
        var highlight = Annotation(kind: .highlight(region: .rect(rect: rect), color: .highlightYellow),
                                   redaction: true)
        highlight.style.opacity = 0.6
        #expect(highlight.solidCover.kind == .rectangle(rect: rect, filled: true, cornerRadius: 0))
        #expect(highlight.solidCover.style.fillColor?.alpha == 1)
        #expect(highlight.coversAsRedaction)
        #expect(!Annotation(kind: .rectangle(rect: rect, filled: false, cornerRadius: 0)).coversAsRedaction)
        let arrow = Annotation(kind: .arrow(start: .zero, end: CGPoint(x: 9, y: 9), style: .straight), redaction: true)
        #expect(arrow.solidCover == arrow)
    }
}

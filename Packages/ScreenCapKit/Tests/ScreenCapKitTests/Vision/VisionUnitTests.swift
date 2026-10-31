import CoreGraphics
import Foundation
@testable import ScreenCapKit
import Testing

@Suite("Vision geometry and text joining")
struct VisionUnitTests {
    @Test func normalizedRectFlipsToTopLeftPixels() {
        let size = CGSize(width: 200, height: 100)
        // Bottom-left quarter in Vision space is the bottom-left quarter in pixels too, but its
        // top-left-origin y is half the height.
        func pixels(_ rect: CGRect) -> CGRect { VisionGeometry.imageRect(fromNormalized: rect, imageSize: size) }
        let rect = pixels(CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        #expect(rect == CGRect(x: 0, y: 50, width: 100, height: 50))

        let top = pixels(CGRect(x: 0.25, y: 0.8, width: 0.5, height: 0.2))
        #expect(top.minX == 50)
        #expect(abs(top.minY) < 1e-9)
        #expect(top.width == 100)
        #expect(abs(top.height - 20) < 1e-9)

        #expect(pixels(CGRect(x: 0, y: 0, width: 1, height: 1)) == CGRect(origin: .zero, size: size))
    }

    private func text(_ lines: String...) -> RecognizedText {
        RecognizedText(lines: lines.map { .init(string: $0, confidence: 1, boundingBox: .zero) })
    }

    @Test func keepLineBreaksJoinsWithNewlines() {
        #expect(text("first line", "recog-", "nition").text(keepLineBreaks: true) == "first line\nrecog-\nnition")
    }

    @Test func stripLineBreaksJoinsWithSpacesAndMergesHyphenatedWords() {
        #expect(text("Text recog-", "nition works").text(keepLineBreaks: false) == "Text recognition works")
        // Real compounds and dashes stay: next line starts uppercase, or no letter before the dash.
        #expect(text("New-", "York").text(keepLineBreaks: false) == "New- York")
        #expect(text("pages 1 -", "end").text(keepLineBreaks: false) == "pages 1 - end")
        #expect(text("  a  ", "", "b").text(keepLineBreaks: false) == "a b")
        #expect(text().text(keepLineBreaks: false).isEmpty)
    }

    @Test func barcodeURLOnlyForHTTPLinks() {
        func url(_ payload: String) -> URL? { Barcode(symbology: "QR", payload: payload, boundingBox: .zero).url }
        #expect(url("https://example.com/test")?.absoluteString == "https://example.com/test")
        #expect(url(" http://example.com ")?.host == "example.com")
        #expect(url("mailto:a@b.c") == nil)
        #expect(url("WIFI:S:net;T:WPA;P:pw;;") == nil)
        #expect(url("just text") == nil)
    }

    @Test func snapHeightPicksLineWithMostOverlap() {
        let lines = [
            CGRect(x: 10, y: 10, width: 300, height: 30),
            CGRect(x: 10, y: 50, width: 300, height: 30),
            CGRect(x: 10, y: 90, width: 300, height: 30)
        ]
        // Thick stroke mostly over line 2 but grazing line 1.
        func snap(_ stroke: CGRect) -> CGRect? { TextLineDetector.snapHeight(for: stroke, lines: lines) }
        #expect(snap(CGRect(x: 20, y: 35, width: 100, height: 30)) == lines[1])
        // Zero-height stroke inside line 3.
        #expect(snap(CGRect(x: 20, y: 100, width: 100, height: 0)) == lines[2])
        // Off to the side or in the gap: nothing to snap to.
        #expect(snap(CGRect(x: 400, y: 50, width: 50, height: 10)) == nil)
        #expect(snap(CGRect(x: 20, y: 42, width: 50, height: 6)) == nil)
    }
}

import CoreGraphics
import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

@Suite("Capture Text outcome")
struct TextCaptureOutcomeTests {
    private func text(_ lines: String...) -> RecognizedText {
        RecognizedText(lines: lines.map { RecognizedText.Line(string: $0, confidence: 1, boundingBox: .zero) })
    }

    private func code(_ payload: String, isQR: Bool = true) -> Barcode {
        let symbology = isQR ? "VNBarcodeSymbologyQR" : "VNBarcodeSymbologyEAN13"
        return Barcode(symbology: symbology, payload: payload, boundingBox: .zero)
    }

    @Test func pluralizesLines() {
        #expect(TextCaptureOutcome.linesMessage(1) == "Copied 1 line")
        #expect(TextCaptureOutcome.linesMessage(3) == "Copied 3 lines")
    }

    @Test func keepsOrStripsLineBreaks() {
        let lines = text("Hello", "world", "  ")
        let kept = TextCaptureOutcome.make(text: lines, barcodes: [], keepLineBreaks: true, copyBarcodePayload: true)
        #expect(kept == TextCaptureOutcome(clipboard: "Hello\nworld", message: "Copied 2 lines", openURL: nil))
        let stripped = TextCaptureOutcome.make(text: lines, barcodes: [], keepLineBreaks: false,
                                               copyBarcodePayload: true)
        #expect(stripped.clipboard == "Hello world")
    }

    @Test func nothingFound() {
        let outcome = TextCaptureOutcome.make(text: text(), barcodes: [], keepLineBreaks: true,
                                              copyBarcodePayload: true)
        #expect(outcome == TextCaptureOutcome(clipboard: nil, message: "No text found", openURL: nil))
    }

    @Test func qrURLWinsAndOffersOpen() {
        let outcome = TextCaptureOutcome.make(text: text("noise"), barcodes: [code("https://example.com")],
                                              keepLineBreaks: true, copyBarcodePayload: true)
        #expect(outcome.clipboard == "https://example.com")
        #expect(outcome.message == "Copied QR code")
        #expect(outcome.openURL == URL(string: "https://example.com"))
    }

    @Test func barcodeAndMultipleCodes() {
        let one = TextCaptureOutcome.make(text: text(), barcodes: [code("4006381333931", isQR: false)],
                                          keepLineBreaks: true, copyBarcodePayload: true)
        #expect(one.message == "Copied barcode")
        #expect(one.openURL == nil)
        let two = TextCaptureOutcome.make(text: text(), barcodes: [code("a"), code("b")],
                                          keepLineBreaks: true, copyBarcodePayload: true)
        #expect(two.clipboard == "a\nb")
        #expect(two.message == "Copied 2 codes")
    }

    @Test func payloadToggleOffFallsBackToText() {
        let outcome = TextCaptureOutcome.make(text: text("Menu"), barcodes: [code("https://example.com")],
                                              keepLineBreaks: true, copyBarcodePayload: false)
        #expect(outcome == TextCaptureOutcome(clipboard: "Menu", message: "Copied 1 line", openURL: nil))
    }
}

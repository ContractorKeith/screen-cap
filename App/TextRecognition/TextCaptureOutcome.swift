import Foundation
import ScreenCapKit

/// What a Capture Text run puts on the pasteboard and says in the HUD. Pure, so it is unit-tested.
struct TextCaptureOutcome: Equatable {
    /// Text for the pasteboard; nil when nothing was found.
    var clipboard: String?
    /// HUD line, e.g. "Copied 3 lines".
    var message: String
    /// A scanned http(s) link the HUD offers to open.
    var openURL: URL?

    /// Decides the outcome. A code wins over OCR text when `copyBarcodePayload` is on,
    /// since a code's payload is what the user meant to grab.
    static func make(text: RecognizedText, barcodes: [Barcode], keepLineBreaks: Bool,
                     copyBarcodePayload: Bool) -> TextCaptureOutcome {
        if copyBarcodePayload, !barcodes.isEmpty {
            let payload = barcodes.map(\.payload).joined(separator: "\n")
            return TextCaptureOutcome(clipboard: payload, message: barcodeMessage(barcodes),
                                      openURL: barcodes.lazy.compactMap(\.url).first)
        }
        let string = text.text(keepLineBreaks: keepLineBreaks)
        guard !string.isEmpty else {
            return TextCaptureOutcome(clipboard: nil, message: "No text found", openURL: nil)
        }
        let count = text.lines.filter { !$0.string.trimmingCharacters(in: .whitespaces).isEmpty }.count
        return TextCaptureOutcome(clipboard: string, message: linesMessage(count), openURL: nil)
    }

    /// "Copied 1 line", "Copied 3 lines".
    static func linesMessage(_ count: Int) -> String {
        "Copied \(count) \(count == 1 ? "line" : "lines")"
    }

    /// "Copied QR code", "Copied barcode", "Copied 2 codes".
    static func barcodeMessage(_ barcodes: [Barcode]) -> String {
        guard barcodes.count == 1, let code = barcodes.first else { return "Copied \(barcodes.count) codes" }
        return code.symbology.uppercased().hasSuffix("QR") ? "Copied QR code" : "Copied barcode"
    }
}

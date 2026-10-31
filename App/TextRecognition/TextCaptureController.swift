import AppKit
import ScreenCapKit

/// App-only Text Recognition preference not in `AppSettings`.
enum TextRecognitionPreferences {
    static let copyBarcodePayloadKey = "ocrCopyBarcodePayload"

    /// Copy a scanned QR/barcode's payload instead of OCR text. On by default.
    static var copyBarcodePayload: Bool {
        UserDefaults.standard.object(forKey: copyBarcodePayloadKey) as? Bool ?? true
    }
}

/// Capture Text: OCR (and QR/barcode reading) of a selected area or an existing image.
///
/// Listens for `.captureTextRequested`. userInfo is either `rect` (NSValue, global points; posted by
/// the coordinator after the selection overlay) or `image` (CGImage; Quick Access, editor), with an
/// optional `recordID` (UUID) or `result` (CaptureResult) naming the history record the text is
/// stored on. A fresh `rect` grab becomes a new `.text` history record (#53).
@MainActor
final class TextCaptureController {
    private let settings: AppSettings
    private let service: CaptureService
    private let history: HistoryStore?
    private let recognizer = TextRecognizer()
    private var observer: NSObjectProtocol?

    init(settings: AppSettings, service: CaptureService, history: HistoryStore?) {
        self.settings = settings
        self.service = service
        self.history = history
    }

    /// Starts observing `.captureTextRequested`.
    func install() {
        observer = NotificationCenter.default.addObserver(
            forName: .captureTextRequested, object: nil, queue: .main
        ) { [weak self] note in
            let request = Self.request(from: note.userInfo)
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.handle(request) }
            }
        }
    }

    /// Reads a `.captureTextRequested` payload. The record ID comes from `recordID`, or from the
    /// `result` Quick Access and the editor send.
    nonisolated static func request(from info: [AnyHashable: Any]?) -> Request {
        let rect = (info?["rect"] as? NSValue)?.rectValue
        let image = cgImage(info?["image"])
        let recordID = info?["recordID"] as? UUID ?? (info?["result"] as? CaptureResult)?.historyRecordID
        return Request(rect: rect, image: image.map(SendableImage.init), recordID: recordID)
    }

    /// A CGImage from a userInfo value, checked by type ID (CF casts always "succeed").
    nonisolated static func cgImage(_ value: Any?) -> CGImage? {
        guard let value, CFGetTypeID(value as CFTypeRef) == CGImage.typeID else { return nil }
        return (value as! CGImage) // swiftlint:disable:this force_cast
    }

    /// CGImage isn't Sendable in every SDK; it is immutable, so wrapping is safe.
    struct SendableImage: @unchecked Sendable {
        let cgImage: CGImage
    }

    struct Request: Sendable {
        var rect: CGRect?
        var image: SendableImage?
        var recordID: UUID?
    }

    private func handle(_ request: Request) async {
        do {
            if let image = request.image?.cgImage {
                try await recognize(image, recordID: request.recordID)
            } else if let rect = request.rect {
                // The overlay just closed; wait for the window server to redraw, then grab the area live.
                try await Task.sleep(for: CaptureCoordinator.overlayHideDelay)
                let captured = try await service.captureArea(pointRect: rect)
                let recordID = await Self.addTextRecord(captured, to: history)
                try await recognize(captured.cgImage, recordID: request.recordID ?? recordID)
            }
        } catch {
            appLog.error("Capture Text failed: \(String(describing: error), privacy: .public)")
            HUDPanel.show("Text recognition failed")
        }
    }

    /// Runs OCR and barcode reading, copies the result and shows the HUD.
    func recognize(_ image: CGImage, recordID: UUID? = nil) async throws {
        let languages = settings.ocrLanguages
        async let codes = BarcodeReader().read(in: image)
        let text = try await recognizer.recognize(in: image, languages: languages)
        let barcodes = (try? await codes) ?? []
        let outcome = TextCaptureOutcome.make(
            text: text, barcodes: barcodes, keepLineBreaks: settings.ocrKeepLineBreaks,
            copyBarcodePayload: TextRecognitionPreferences.copyBarcodePayload
        )
        if let clipboard = outcome.clipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(clipboard, forType: .string)
        }
        appLog.notice("Capture Text: \(outcome.message, privacy: .public)")
        if let url = outcome.openURL {
            HUDPanel.show(outcome.message, buttonTitle: "Open") { NSWorkspace.shared.open(url) }
        } else {
            HUDPanel.show(outcome.message)
        }
        if let recordID, let history, !text.isEmpty {
            await Self.storeText(text.text(keepLineBreaks: true), recordID: recordID, in: history)
        }
    }

    /// Adds a fresh Capture Text grab to history as a `.text` record so its text is searchable.
    static func addTextRecord(_ image: CapturedImage, to history: HistoryStore?) async -> UUID? {
        guard let history else { return nil }
        do {
            return try await history.add(image: image.cgImage, kind: .text,
                                         metadata: CaptureMetadata(scale: Double(image.scale))).id
        } catch {
            appLog.error("History write failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Stores OCR text on a history record for search, then lets an open History window reload.
    static func storeText(_ text: String, recordID: UUID, in history: HistoryStore) async {
        do {
            _ = try await history.setOCRText(id: recordID, text: text)
            NotificationCenter.default.post(name: .historyRecordsChanged, object: nil)
        } catch {
            appLog.error("History OCR update failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

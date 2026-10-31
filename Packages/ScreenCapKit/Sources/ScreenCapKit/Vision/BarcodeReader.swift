import CoreGraphics
import Foundation
import Vision

/// A decoded QR code or barcode.
public struct Barcode: Sendable, Equatable {
    /// `VNBarcodeSymbology` raw value, e.g. `VNBarcodeSymbology.qr.rawValue`.
    public var symbology: String
    public var payload: String
    /// Bounding box in image pixels, top-left origin.
    public var boundingBox: CGRect

    public init(symbology: String, payload: String, boundingBox: CGRect) {
        self.symbology = symbology
        self.payload = payload
        self.boundingBox = boundingBox
    }

    /// The payload as a URL when it is an http(s) link, so the UI can offer to open it.
    public var url: URL? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false
        else { return nil }
        return url
    }
}

/// Reads QR codes and barcodes with `VNDetectBarcodesRequest`.
public struct BarcodeReader: Sendable {
    public init() {}

    /// Every barcode with a string payload found in `image`.
    public func read(in image: CGImage) async throws -> [Barcode] {
        try await VisionGeometry.perform {
            let request = VNDetectBarcodesRequest()
            try VNImageRequestHandler(cgImage: image).perform([request])

            let size = VisionGeometry.size(of: image)
            return (request.results ?? []).compactMap { observation in
                guard let payload = observation.payloadStringValue else { return nil }
                return Barcode(
                    symbology: observation.symbology.rawValue,
                    payload: payload,
                    boundingBox: VisionGeometry.imageRect(fromNormalized: observation.boundingBox, imageSize: size)
                )
            }
        }
    }
}

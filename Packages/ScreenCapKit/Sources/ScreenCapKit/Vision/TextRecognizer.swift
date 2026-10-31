import CoreGraphics
import Foundation
import Vision

/// On-device OCR with `VNRecognizeTextRequest`.
public actor TextRecognizer {
    /// Speed/accuracy trade-off, mirrors `VNRequestTextRecognitionLevel`.
    public enum Level: Sendable {
        case accurate
        case fast

        var vision: VNRequestTextRecognitionLevel {
            switch self {
            case .accurate: .accurate
            case .fast: .fast
            }
        }
    }

    public init() {}

    /// Recognizes text in `image`. With `languages == nil` Vision detects the language itself.
    public func recognize(
        in image: CGImage,
        languages: [String]? = nil,
        level: Level = .accurate,
        usesLanguageCorrection: Bool = true
    ) async throws -> RecognizedText {
        try await Self.recognize(
            in: image, languages: languages, level: level, usesLanguageCorrection: usesLanguageCorrection
        )
    }

    /// Language codes (e.g. "en-US", "ja-JP") Vision can recognize at `level`.
    public func supportedLanguages(level: Level = .accurate) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level.vision
        return try request.supportedRecognitionLanguages()
    }

    /// Shared, actor-free implementation (also used by `TextLineDetector`).
    static func recognize(
        in image: CGImage,
        languages: [String]?,
        level: Level,
        usesLanguageCorrection: Bool
    ) async throws -> RecognizedText {
        try await VisionGeometry.perform {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = level.vision
            request.usesLanguageCorrection = usesLanguageCorrection
            if let languages, !languages.isEmpty {
                request.recognitionLanguages = languages
                request.automaticallyDetectsLanguage = false
            } else {
                request.automaticallyDetectsLanguage = true
            }
            try VNImageRequestHandler(cgImage: image).perform([request])

            let size = VisionGeometry.size(of: image)
            let lines = (request.results ?? []).compactMap { observation -> RecognizedText.Line? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return RecognizedText.Line(
                    string: candidate.string,
                    confidence: candidate.confidence,
                    boundingBox: VisionGeometry.imageRect(fromNormalized: observation.boundingBox, imageSize: size)
                )
            }
            return RecognizedText(lines: lines)
        }
    }
}

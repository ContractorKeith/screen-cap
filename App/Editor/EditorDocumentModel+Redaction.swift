import CoreGraphics
import Foundation
import ScreenCapKit

// Opaque shapes as redactions (#74): "Use as redaction" flags, resolved against Vision's text lines.

/// Text lines found in one base image.
struct DetectedText {
    let image: CGImage
    let lines: [CGRect]
}

extension EditorDocumentModel {
    /// Text lines in the current base image, if detection has finished for it.
    var textLines: [CGRect] {
        guard let detectedText, detectedText.image === baseImage else { return [] }
        return detectedText.lines
    }

    /// Runs (or joins) text detection for the current base image and returns its lines.
    /// Detection failures count as no text.
    @discardableResult
    func detectedTextLines() async -> [CGRect] {
        let image = baseImage
        if let detectedText, detectedText.image === image { return detectedText.lines }
        let task = textDetection ?? Task.detached(priority: .userInitiated) {
            (try? await TextLineDetector().lines(in: image)) ?? []
        }
        textDetection = task
        let lines = await task.value
        textDetection = nil
        // A crop or rotate during detection made a new image; detect again for it.
        guard image === baseImage else { return await detectedTextLines() }
        detectedText = DetectedText(image: image, lines: lines)
        touch()
        return lines
    }

    /// The flag the inspector shows: explicit if set, else automatic.
    func isRedaction(_ annotation: Annotation) -> Bool {
        annotation.resolvedRedaction(textLines: textLines)
    }

    /// The document as it's written: automatic flags that resolve to on become `true`.
    var documentForSave: Document {
        document.resolvingRedactions(textLines: textLines)
    }

    /// Opaque shapes the save warning lists: automatic, opaque, and not over detected text.
    var unmarkedOpaqueCovers: [Annotation] {
        document.unmarkedOpaqueCovers(textLines: textLines)
    }

    /// Sets "Use as redaction" on `ids` in one undo step.
    func setRedaction(_ isOn: Bool, for ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        edit { document in
            for index in document.annotations.indices where ids.contains(document.annotations[index].id) {
                document.annotations[index].redaction = isOn
            }
        }
    }
}

extension Annotation {
    /// Short name for the save warning's list.
    var displayName: String {
        switch kind {
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .highlight: "Highlight"
        case .text: "Text label"
        default: "Shape"
        }
    }
}

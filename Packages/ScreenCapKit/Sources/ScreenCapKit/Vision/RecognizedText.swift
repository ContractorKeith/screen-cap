import CoreGraphics
import Foundation

/// OCR output: recognized lines in reading order.
public struct RecognizedText: Sendable, Equatable {
    /// One recognized line of text.
    public struct Line: Sendable, Equatable {
        public var string: String
        /// Vision's confidence, 0...1.
        public var confidence: Float
        /// Bounding box in image pixels, top-left origin.
        public var boundingBox: CGRect

        public init(string: String, confidence: Float, boundingBox: CGRect) {
            self.string = string
            self.confidence = confidence
            self.boundingBox = boundingBox
        }
    }

    public var lines: [Line]

    public init(lines: [Line]) {
        self.lines = lines
    }

    public var isEmpty: Bool { lines.isEmpty }

    /// Joins lines with newlines (`keepLineBreaks`) or single spaces.
    ///
    /// When stripping line breaks, a word split across lines with a trailing hyphen
    /// ("recog-" + "nition") is rejoined without the hyphen. Keeping line breaks preserves
    /// the text exactly as laid out.
    public func text(keepLineBreaks: Bool) -> String {
        let strings = lines.map { $0.string.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if keepLineBreaks { return strings.joined(separator: "\n") }

        var result = ""
        for line in strings {
            if result.isEmpty {
                result = line
            } else if Self.endsWithSplitWord(result), line.first?.isLowercase == true {
                result.removeLast()
                result += line
            } else {
                result += " " + line
            }
        }
        return result
    }

    /// True when the text ends in "letter-", i.e. a word hyphenated at the line end.
    private static func endsWithSplitWord(_ text: String) -> Bool {
        guard text.count >= 2, let last = text.last, last == "-" || last == "\u{00AD}" else { return false }
        return text.dropLast().last?.isLetter == true
    }
}

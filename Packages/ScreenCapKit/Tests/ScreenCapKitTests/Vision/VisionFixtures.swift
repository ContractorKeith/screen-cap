import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import Foundation

/// Test images generated in code (no binary fixtures).
enum VisionFixtures {
    static let scale: CGFloat = 2

    /// A white image at 2x with `text` laid out by CoreText in a `pointWidth`-wide column.
    static func paragraph(_ text: String, font: String, size: CGFloat, pointWidth: CGFloat = 520) -> CGImage {
        let attributed = attributedString(text, font: font, size: size)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let margin: CGFloat = 20
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(), nil, CGSize(width: pointWidth, height: .greatestFiniteMagnitude), nil
        )
        let pointSize = CGSize(width: pointWidth + margin * 2, height: ceil(fit.height) + margin * 2)
        return render(pointSize: pointSize) { context in
            let frameRect = CGRect(x: margin, y: margin, width: pointWidth, height: ceil(fit.height))
            let path = CGPath(rect: frameRect, transform: nil)
            CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(), path, nil), context)
        }
    }

    /// Separate lines drawn at known positions. Returns the image and each line's vertical
    /// band in image pixels (top-left origin), so tests can aim a stroke without using Vision.
    static func lines(_ lines: [String], font: String, size: CGFloat, spacing: CGFloat)
        -> (image: CGImage, bands: [ClosedRange<CGFloat>]) {
        let pointSize = CGSize(width: 520, height: spacing * CGFloat(lines.count + 1))
        var bands: [ClosedRange<CGFloat>] = []
        let image = render(pointSize: pointSize) { context in
            for (index, string) in lines.enumerated() {
                let line = CTLineCreateWithAttributedString(attributedString(string, font: font, size: size))
                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                CTLineGetTypographicBounds(line, &ascent, &descent, nil)
                let topFromTop = spacing * CGFloat(index + 1) - ascent
                let baseline = pointSize.height - topFromTop - ascent
                context.textPosition = CGPoint(x: 20, y: baseline)
                CTLineDraw(line, context)
                bands.append((topFromTop * scale)...((topFromTop + ascent + descent) * scale))
            }
        }
        return (image, bands)
    }

    /// A QR code for `payload` with a white quiet zone, upscaled so Vision reads it easily.
    static func qrCode(_ payload: String) throws -> CGImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { throw FixtureError.render }
        let code = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let codeImage = context.createCGImage(code, from: code.extent) else { throw FixtureError.render }

        let padding: CGFloat = 80
        let side = code.extent.width + padding * 2
        return render(pointSize: CGSize(width: side / scale, height: side / scale)) { context in
            context.scaleBy(x: 1 / scale, y: 1 / scale)
            context.interpolationQuality = .none
            context.draw(codeImage, in: CGRect(origin: CGPoint(x: padding, y: padding), size: code.extent.size))
        }
    }

    enum FixtureError: Error { case render }

    private static func attributedString(_ text: String, font: String, size: CGFloat) -> CFAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(font as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ]
        return NSAttributedString(string: text, attributes: attributes)
    }

    /// White RGB bitmap at `scale`; drawing happens in points with a bottom-left origin.
    private static func render(pointSize: CGSize, draw: (CGContext) -> Void) -> CGImage {
        let width = Int(ceil(pointSize.width * scale))
        let height = Int(ceil(pointSize.height * scale))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { fatalError("Could not create bitmap context") }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        draw(context)
        guard let image = context.makeImage() else { fatalError("Could not render fixture") }
        return image
    }
}

/// Character accuracy = 1 - editDistance / expectedLength.
enum TextAccuracy {
    static func characterAccuracy(expected: String, actual: String) -> Double {
        let expectedChars = Array(expected)
        guard !expectedChars.isEmpty else { return actual.isEmpty ? 1 : 0 }
        let distance = levenshtein(expectedChars, Array(actual))
        return max(0, 1 - Double(distance) / Double(expectedChars.count))
    }

    static func levenshtein(_ lhs: [Character], _ rhs: [Character]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }
        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)
        for (row, left) in lhs.enumerated() {
            current[0] = row + 1
            for (col, right) in rhs.enumerated() {
                let substitution = previous[col] + (left == right ? 0 : 1)
                current[col + 1] = min(previous[col + 1] + 1, current[col] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }

    /// Collapses whitespace runs to one space (OCR reflows lines, so layout whitespace isn't scored).
    static func collapsingWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Drops all whitespace (CJK text has no word spaces, so joined lines must not be penalized).
    static func removingWhitespace(_ text: String) -> String {
        String(text.filter { !$0.isWhitespace })
    }
}

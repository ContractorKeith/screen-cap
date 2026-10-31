// Fixture builders and pixel readers for Effects tests.
import CoreGraphics
import CoreText
import Foundation
@testable import ScreenCapKit
import Vision

enum EffectsFixtures {
    /// A bitmap of the given size filled with `color`; `draw` runs in CG (bottom-left) space.
    static func image(
        width: Int, height: Int, fill color: RGBAColor?, draw: (CGContext) -> Void = { _ in }
    ) throws -> CGImage {
        let bitmap = try EffectsBitmap(width: width, height: height)
        if let color {
            bitmap.context.setFillColor(color.cgColor)
            bitmap.context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        draw(bitmap.context)
        return try bitmap.makeImage()
    }

    /// Black text on white, drawn with CoreText.
    static func textImage(
        _ text: String, width: Int = 760, height: Int = 100, fontSize: CGFloat = 40
    ) throws -> CGImage {
        try image(width: width, height: height, fill: .white) { context in
            let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): RGBAColor.black.cgColor
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            context.textPosition = CGPoint(x: 20, y: 35)
            CTLineDraw(line, context)
        }
    }

    /// Premultiplied RGBA bytes of pixel `(x, y)` in top-left coordinates.
    static func pixel(_ image: CGImage, x: Int, y: Int) throws -> [Int] {
        let bitmap = try EffectsBitmap(image: image)
        let index = bitmap.offset(x: x, y: y)
        return (0..<4).map { Int(bitmap.pixels[index + $0]) }
    }

    static func bytes(_ image: CGImage) throws -> [UInt8] {
        let bitmap = try EffectsBitmap(image: image)
        return Array(UnsafeBufferPointer(start: bitmap.pixels, count: bitmap.bytesPerRow * bitmap.height))
    }

    /// Every candidate string Vision recognizes (top 3 per observation).
    static func recognizedText(in image: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).flatMap { $0.topCandidates(3).map(\.string) }
    }
}

import CoreGraphics
import CoreText
import Foundation

/// Rendered-text pages from the 2026-10-31 skeptic pass #2 harness (#70, #71): 200 rows of 30 px
/// on a 600 px wide white page, cut into 600 px viewport frames at given scroll positions.
enum TextScrollFixtures {
    static let width = 600
    static let rowHeight = 30
    static let viewport = 600

    /// Terminal: `$ make test` repeated, with a unique `== build n ==` line every 25 rows.
    static let terminal: CGImage = page((0..<200).map { $0 % 25 == 0 ? "== build \($0) ==" : "$ make test" },
                                        font: "Menlo")
    /// Table: three identical rows and a rule, repeating (fully periodic every 120 px).
    static let table: CGImage = page((0..<200).map { $0 % 4 == 3 ? "---" : "same row text" }, font: "Helvetica")
    /// Unique text rows.
    static let unique: CGImage = page((0..<200).map { "Row \($0): the quick brown fox \($0 * 7919 % 1000)" },
                                      font: "Helvetica")

    /// The harness's irregular hand scroll.
    static let handScroll = positions([37, 120, 0, 190, 64, 250, 33, 400, 90, 15, 300, 120])

    /// Scroll positions (top of each frame) after each step, starting at 0.
    static func positions(_ steps: [Int]) -> [Int] {
        steps.reduce(into: [0]) { result, step in result.append((result.last ?? 0) + step) }
    }

    /// The viewport frame whose top is `top` pixels down the page.
    static func frame(_ page: CGImage, at top: Int, length: Int = viewport) -> CGImage {
        // Fixture sizes are always valid. swiftlint:disable:next force_unwrapping
        page.cropping(to: CGRect(x: 0, y: top, width: page.width, height: length))!
    }

    /// The first `length` pixels of the page.
    static func prefix(_ page: CGImage, _ length: Int) -> CGImage { frame(page, at: 0, length: length) }

    private static func page(_ lines: [String], font name: String) -> CGImage {
        let height = lines.count * rowHeight
        // Fixture sizes are always valid, so these force unwraps cannot fail.
        // swiftlint:disable force_unwrapping
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName(name as CFString, 22, nil)
        for (index, text) in lines.enumerated() {
            let bottom = height - (index + 1) * rowHeight
            if text == "---" {
                context.setFillColor(CGColor(gray: 0.6, alpha: 1))
                context.fill(CGRect(x: 0, y: bottom + rowHeight / 2, width: width, height: 2))
                continue
            }
            let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            context.textPosition = CGPoint(x: 10, y: CGFloat(bottom) + CGFloat(rowHeight) * 0.3)
            CTLineDraw(line, context)
        }
        return context.makeImage()!
        // swiftlint:enable force_unwrapping
    }
}

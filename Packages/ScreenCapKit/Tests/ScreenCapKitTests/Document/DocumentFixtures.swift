import CoreGraphics
import Foundation
@testable import ScreenCapKit

/// Shared fixtures for the Document tests.
enum DocumentFixtures {
    /// One annotation of every kind, including every arrow style and highlight/spotlight variant.
    static let everyKind: [Annotation.Kind] = [
        .arrow(start: CGPoint(x: 10, y: 20), end: CGPoint(x: 110, y: 80), style: .straight),
        .arrow(start: CGPoint(x: 10, y: 20), end: CGPoint(x: 110, y: 80), style: .tapered),
        .arrow(start: CGPoint(x: 10, y: 20), end: CGPoint(x: 110, y: 80), style: .doubleHeaded),
        .arrow(start: CGPoint(x: 10, y: 20), end: CGPoint(x: 110, y: 80),
               style: .curved(control: CGPoint(x: 60, y: 5))),
        .rectangle(rect: CGRect(x: 5, y: 6, width: 70, height: 40), filled: false, cornerRadius: 0),
        .rectangle(rect: CGRect(x: 5, y: 6, width: 70, height: 40), filled: true, cornerRadius: 8),
        .ellipse(rect: CGRect(x: 0, y: 0, width: 30, height: 20)),
        .line(start: CGPoint(x: 1, y: 2), end: CGPoint(x: 3.5, y: 4.25)),
        .text(string: "Hello \"world\" ✓", preset: 7, fontSize: 24,
              rect: CGRect(x: 40, y: 40, width: 200, height: 32)),
        .counter(number: 3, center: CGPoint(x: 50, y: 50), radius: 14),
        .path(points: [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 9), CGPoint(x: 12, y: 3)], smoothed: true),
        .highlight(region: .rect(rect: CGRect(x: 0, y: 100, width: 300, height: 18)), color: .highlightYellow),
        .highlight(region: .path(points: [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 2)]), color: .highlightYellow),
        .blur(rect: CGRect(x: 10, y: 10, width: 50, height: 50), mode: .secure, radius: 12),
        .blur(rect: CGRect(x: 10, y: 10, width: 50, height: 50), mode: .smooth, radius: 6),
        .pixelate(rect: CGRect(x: 0, y: 0, width: 64, height: 64), blockSize: 8, randomize: true),
        .spotlight(shapes: [
            .rect(rect: CGRect(x: 0, y: 0, width: 10, height: 10)),
            .ellipse(rect: CGRect(x: 20, y: 20, width: 5, height: 5))
        ]),
        .imageLayer(layerName: "pasted-1", rect: CGRect(x: 30, y: 30, width: 64, height: 32))
    ]

    static let base = Document.BaseImage(pixelWidth: 400, pixelHeight: 300, scale: 2)

    static func counter(_ number: Int, x: Double = 0) -> Annotation {
        Annotation(kind: .counter(number: number, center: CGPoint(x: x, y: 0), radius: 10))
    }

    static func counterNumbers(_ document: Document) -> [Int] {
        document.annotations.compactMap {
            if case let .counter(number, _, _) = $0.kind { return number }
            return nil
        }
    }

    /// A solid-color RGBA image of the given pixel size.
    static func image(width: Int, height: Int, red: CGFloat = 1, green: CGFloat = 0, blue: CGFloat = 0) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}

import CoreGraphics
import Foundation
import ScreenCapKit

/// The 20 built-in Background tool images, generated procedurally at runtime (no asset files)
/// and cached by name. Names are stored in documents as `BackgroundFill.bundled(name:)`, so
/// never rename one.
@MainActor
enum BundledBackgrounds {
    static let size = CGSize(width: 1600, height: 1000)

    /// How one background is drawn.
    enum Recipe {
        case linear([UInt32], angle: Double)
        case blobs(base: UInt32, [UInt32])
        case stripes(UInt32, UInt32, width: Double)
        case dots(base: UInt32, dot: UInt32, spacing: Double)
        case waves(UInt32, UInt32, bands: Int)
        case rays(UInt32, UInt32, count: Int)
    }

    static let recipes: [(name: String, recipe: Recipe)] = [
        ("Dawn", .linear([0xFF9A8B, 0xFF6A88, 0xFF99AC], angle: 135)),
        ("Lagoon", .linear([0x13547A, 0x80D0C7], angle: 90)),
        ("Citrus", .linear([0xF6D365, 0xFDA085], angle: 45)),
        ("Dusk", .linear([0x2E3192, 0x1BFFFF], angle: 160)),
        ("Meadow", .linear([0x96E6A1, 0xD4FC79], angle: 20)),
        ("Plum", .linear([0x4A00E0, 0x8E2DE2], angle: 120)),
        ("Graphite", .linear([0x232526, 0x414345], angle: 90)),
        ("Paper", .linear([0xFDFBFB, 0xEBEDEE], angle: 90)),
        ("Aurora", .blobs(base: 0x0B1026, [0x00C9A7, 0x845EC2, 0x4D8076, 0x2C73D2])),
        ("Sorbet", .blobs(base: 0xFFE3E3, [0xFFB4A2, 0xFFCDB2, 0xB5838D, 0xE5989B])),
        ("Glacier", .blobs(base: 0xE0F7FA, [0x80DEEA, 0x4FC3F7, 0xB3E5FC, 0x81D4FA])),
        ("Ember", .blobs(base: 0x1A0A0A, [0xFF5F6D, 0xFFC371, 0xC31432, 0x8E0E00])),
        ("Candy Stripe", .stripes(0xFFD6E0, 0xFFEFF3, width: 40)),
        ("Slate Stripe", .stripes(0x2B2D42, 0x33364D, width: 28)),
        ("Polka", .dots(base: 0x5B5F97, dot: 0x7B7FB7, spacing: 48)),
        ("Grid Dots", .dots(base: 0xF4F1EA, dot: 0xD9D2C3, spacing: 32)),
        ("Tide", .waves(0x0F4C75, 0x3282B8, bands: 7)),
        ("Dune", .waves(0xE6B17E, 0xF2D0A4, bands: 6)),
        ("Sunburst", .rays(0xFFB703, 0xFB8500, count: 24)),
        ("Nebula Rays", .rays(0x240046, 0x3C096C, count: 32))
    ]

    static var names: [String] { recipes.map(\.name) }

    private static var cache: [String: CGImage] = [:]

    /// The background image for `name`, drawn on first use. Nil for unknown names.
    static func image(named name: String) -> CGImage? {
        if let cached = cache[name] { return cached }
        guard let recipe = recipes.first(where: { $0.name == name })?.recipe,
              let image = draw(recipe, size: size) else { return nil }
        cache[name] = image
        return image
    }

    /// Small version for the Background panel's swatches.
    static func thumbnail(named name: String) -> CGImage? {
        guard let recipe = recipes.first(where: { $0.name == name })?.recipe else { return nil }
        return draw(recipe, size: CGSize(width: 96, height: 60), scale: 0.06)
    }

    static func draw(_ recipe: Recipe, size: CGSize, scale: Double = 1) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(origin: .zero, size: size)
        switch recipe {
        case let .linear(colors, angle): linear(colors, angle: angle, rect: rect, context: context)
        case let .blobs(base, colors): blobs(base: base, colors, rect: rect, context: context)
        case let .stripes(first, second, width):
            stripes(first, second, width: width * scale, rect: rect, context: context)
        case let .dots(base, dot, spacing):
            dots(base: base, dot: dot, spacing: spacing * scale, rect: rect, context: context)
        case let .waves(first, second, bands): waves(first, second, bands: bands, rect: rect, context: context)
        case let .rays(first, second, count): rays(first, second, count: count, rect: rect, context: context)
        }
        return context.makeImage()
    }

    // MARK: - Painters

    static func color(_ hex: UInt32, alpha: Double = 1) -> CGColor {
        CGColor(srgbRed: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255, alpha: alpha)
    }

    private static func linear(_ colors: [UInt32], angle: Double, rect: CGRect, context: CGContext) {
        let locations = colors.indices.map { CGFloat($0) / CGFloat(max(colors.count - 1, 1)) }
        let cgColors = colors.map { color($0) } as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: cgColors,
                                        locations: locations) else { return }
        let radians = angle * .pi / 180
        let half = (abs(rect.width * cos(radians)) + abs(rect.height * sin(radians))) / 2
        let start = CGPoint(x: rect.midX - cos(radians) * half, y: rect.midY - sin(radians) * half)
        let end = CGPoint(x: rect.midX + cos(radians) * half, y: rect.midY + sin(radians) * half)
        context.drawLinearGradient(gradient, start: start, end: end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// Soft radial color fields over a base, like a blurred mesh gradient.
    private static func blobs(base: UInt32, _ colors: [UInt32], rect: CGRect, context: CGContext) {
        context.setFillColor(color(base))
        context.fill(rect)
        let anchors = [CGPoint(x: 0.15, y: 0.2), CGPoint(x: 0.85, y: 0.3), CGPoint(x: 0.3, y: 0.85),
                       CGPoint(x: 0.75, y: 0.8)]
        for (index, hex) in colors.enumerated() {
            let anchor = anchors[index % anchors.count]
            let center = CGPoint(x: rect.width * anchor.x, y: rect.height * anchor.y)
            guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                            colors: [color(hex, alpha: 0.9), color(hex, alpha: 0)] as CFArray,
                                            locations: [0, 1]) else { continue }
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                       endRadius: max(rect.width, rect.height) * 0.6, options: [])
        }
    }

    private static func stripes(_ first: UInt32, _ second: UInt32, width: Double, rect: CGRect, context: CGContext) {
        context.setFillColor(color(first))
        context.fill(rect)
        context.setFillColor(color(second))
        let step = max(width, 2) * 2
        var x = -rect.height
        while x < rect.width {
            let path = CGMutablePath()
            path.addLines(between: [CGPoint(x: x, y: 0), CGPoint(x: x + step / 2, y: 0),
                                    CGPoint(x: x + step / 2 + rect.height, y: rect.height),
                                    CGPoint(x: x + rect.height, y: rect.height)])
            context.addPath(path)
            context.fillPath()
            x += step
        }
    }

    private static func dots(base: UInt32, dot: UInt32, spacing: Double, rect: CGRect, context: CGContext) {
        context.setFillColor(color(base))
        context.fill(rect)
        context.setFillColor(color(dot))
        let gap = max(spacing, 4), radius = gap * 0.18
        var y = gap / 2
        while y < rect.height {
            var x = gap / 2
            while x < rect.width {
                context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                x += gap
            }
            y += gap
        }
    }

    /// Stacked sine bands blending from `first` to `second`.
    private static func waves(_ first: UInt32, _ second: UInt32, bands: Int, rect: CGRect, context: CGContext) {
        context.setFillColor(color(first))
        context.fill(rect)
        for band in 0..<bands {
            let fraction = Double(band + 1) / Double(bands + 1)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0))
            for step in 0...64 {
                let x = rect.width * Double(step) / 64
                let y = rect.height * fraction + sin(Double(step) / 64 * .pi * 2 + Double(band)) * rect.height * 0.05
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: rect.width, y: 0))
            path.closeSubpath()
            context.addPath(path)
            context.setFillColor(color(second, alpha: 0.18))
            context.fillPath()
        }
    }

    private static func rays(_ first: UInt32, _ second: UInt32, count: Int, rect: CGRect, context: CGContext) {
        context.setFillColor(color(first))
        context.fill(rect)
        context.setFillColor(color(second))
        let center = CGPoint(x: rect.midX, y: rect.midY * 0.6)
        let reach = hypot(rect.width, rect.height)
        let slice = 2 * Double.pi / Double(count * 2)
        for index in 0..<count {
            let angle = Double(index * 2) * slice
            let path = CGMutablePath()
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x + cos(angle) * reach, y: center.y + sin(angle) * reach))
            path.addLine(to: CGPoint(x: center.x + cos(angle + slice) * reach,
                                     y: center.y + sin(angle + slice) * reach))
            path.closeSubpath()
            context.addPath(path)
            context.fillPath()
        }
    }
}

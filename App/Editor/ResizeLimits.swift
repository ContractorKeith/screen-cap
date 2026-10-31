import CoreGraphics
import Foundation

/// Bounds for the Resize dialog, so a typo (an extra zero) can't start an allocation the Mac
/// can't satisfy (#110). 16 384 px per side and 64 MP total: about 256 MB per RGBA bitmap.
enum ResizeLimits {
    static let maxSide = 16_384
    static let maxPixels = 64_000_000

    enum Verdict: Equatable {
        /// Valid integral pixel size.
        case valid(CGSize)
        /// Why the size can't be used, for the dialog.
        case invalid(String)

        var size: CGSize? { if case let .valid(size) = self { size } else { nil } }
        var message: String? { if case let .invalid(message) = self { message } else { nil } }
    }

    /// Checks typed width and height; nil means the field doesn't hold a number.
    static func validate(width: Double?, height: Double?) -> Verdict {
        guard let width, let height else { return .invalid("Enter a width and height in pixels.") }
        guard width.isFinite, height.isFinite else { return .invalid("Enter a width and height in pixels.") }
        let side = Double(maxSide)
        guard width.rounded() >= 1, height.rounded() >= 1 else {
            return .invalid("Width and height must be at least 1 px.")
        }
        guard width.rounded() <= side, height.rounded() <= side else {
            return .invalid("Width and height can be at most \(grouped(maxSide)) px.")
        }
        let size = CGSize(width: width.rounded(), height: height.rounded())
        guard size.width * size.height <= Double(maxPixels) else {
            return .invalid("At most \(maxPixels / 1_000_000) megapixels (this is \(megapixels(size)) MP).")
        }
        return .valid(size)
    }

    static func validate(_ size: CGSize) -> Verdict {
        validate(width: Double(size.width), height: Double(size.height))
    }

    /// Parses a typed number ("2940", "2,940", "2940.5"); nil for empty, garbage or non-finite text.
    static func parse(_ text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        let value = formatter.number(from: trimmed)?.doubleValue ?? Double(trimmed)
        guard let value, value.isFinite else { return nil }
        return value
    }

    /// Integer text for a field, without grouping so it parses back the same.
    static func text(_ value: Double) -> String {
        value.isFinite && abs(value) < 1e15 ? String(Int(value.rounded())) : ""
    }

    private static func grouped(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    private static func megapixels(_ size: CGSize) -> String {
        let value = size.width * size.height / 1_000_000
        return value >= 1000 ? Int(value).formatted() : String(format: "%.1f", value)
    }
}

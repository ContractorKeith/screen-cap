import Foundation

/// Strict number parsing shared by the URL scheme and the hidden launch options (#102, #105).
public enum StrictNumber {
    /// Plain decimals only (`12`, `12.5`, `.5`): no sign, hex, exponent, `_`, `inf`/`nan` or
    /// whitespace, all of which `Double(_:)` accepts.
    public static func decimal(_ raw: String) -> Double? {
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts.contains(where: { !$0.isEmpty }),
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        return Double(raw).flatMap { $0.isFinite ? $0 : nil }
    }

    /// `decimal` with an optional leading `-` (global coordinates can be negative).
    public static func signedDecimal(_ raw: String) -> Double? {
        guard raw.hasPrefix("-") else { return decimal(raw) }
        return decimal(String(raw.dropFirst())).map { -$0 }
    }
}

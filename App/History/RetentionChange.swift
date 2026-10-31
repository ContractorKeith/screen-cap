import Foundation

/// Shortening "Keep captures for" deletes captures at once, so it asks first (#101).
/// Pure decision logic; `AdvancedSettingsPane` shows the dialog and applies the result.
struct RetentionChange: Equatable {
    let current: Int
    let proposed: Int
    /// Captures older than `proposed` days, which the change would delete.
    let count: Int

    enum Decision: Equatable {
        /// Nothing would be deleted: set `days` right away.
        case apply(Int)
        /// Ask before deleting.
        case confirm(RetentionChange)
    }

    static func decide(from current: Int, to proposed: Int, expiring count: Int) -> Decision {
        guard proposed < current, count > 0 else { return .apply(proposed) }
        return .confirm(RetentionChange(current: current, proposed: proposed, count: count))
    }

    var title: String {
        let captures = count == 1 ? "1 capture" : "\(count) captures"
        return "Delete \(captures) older than \(Self.days(proposed))?"
    }

    var message: String {
        "Keeping captures for \(Self.days(proposed)) instead of \(Self.days(current)) deletes "
            + (count == 1 ? "it" : "them") + " from History now. This can't be undone."
    }

    /// The setting to keep: the new value when confirmed, else the old one (Cancel reverts).
    func resolve(confirmed: Bool) -> Int { confirmed ? proposed : current }

    static func days(_ value: Int) -> String { value == 1 ? "1 day" : "\(value) days" }
}

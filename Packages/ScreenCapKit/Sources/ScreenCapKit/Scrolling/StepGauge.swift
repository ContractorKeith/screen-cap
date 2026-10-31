// The auto-scroll step as the page actually moves it (#112).

/// Learns how far content moves per posted scroll pixel from frames that lined up unambiguously,
/// and predicts the offsets of later frames from it. Terminal, for one, moves about 1.5× what is
/// posted. The median of all samples, so one mismeasured frame can't take over.
struct StepGauge {
    /// Content pixels moved per posted pixel, one per measurement.
    private var samples: [Double] = []

    /// The measured content pixels per posted pixel; nil until something was measured.
    var scale: Double? {
        guard !samples.isEmpty else { return nil }
        return samples.sorted()[samples.count / 2]
    }

    /// Steps of `unit` pixels in `posted` (`unit` nil: one step of `posted`).
    private static func steps(posted: Int, unit: Int?) -> (count: Int, unit: Int) {
        let unit = unit.map { max(1, min($0, posted)) } ?? posted
        return (max(1, Int((Double(posted) / Double(unit)).rounded())), unit)
    }

    /// Offsets predicted for `posted` pixels in steps of `unit`: every step taken first, then
    /// fewer (steps the page dropped). Empty until something was measured.
    func predictedOffsets(posted: Int?, unit: Int?) -> [Int] {
        guard let scale, let posted, posted > 0 else { return [] }
        let steps = Self.steps(posted: posted, unit: unit)
        return (1...steps.count).reversed().map { Int((scale * Double($0 * steps.unit)).rounded()) }
    }

    /// Records that content moved `offset` pixels while `posted` pixels were posted.
    mutating func measure(offset: Int, posted: Int?, unit: Int?) {
        guard let posted, posted > 0, offset > 0 else { return }
        let steps = Self.steps(posted: posted, unit: unit)
        // Fewer steps than posted when the page dropped some: the count nearest what's measured.
        let taken = scale.map { scale in
            min(steps.count, max(1, Int((Double(offset) / (scale * Double(steps.unit))).rounded())))
        } ?? steps.count
        samples.append(Double(offset) / Double(taken * steps.unit))
    }
}

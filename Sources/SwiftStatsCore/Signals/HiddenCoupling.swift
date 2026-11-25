//
//  HiddenCoupling.swift
//  SwiftStatsCore
//
//  Hidden coupling (PRD §8, M7, design §8.1, D14): pairs of production
//  families that change together often, by the history window's commits,
//  with no static dependency between them, by the T1 build's index. The
//  rule is stated here so a left-out signal says what it judges; the pairs
//  are judged in plan step 9c, and until then the engine leaves the
//  signal out as not built yet once its requirements hold.
//

/// The hidden coupling signal.
enum HiddenCoupling {
    /// The limits a listed pair meets.
    struct Limits {
        /// Commits in the window changing both families, at least.
        let support: Double
        /// Support as a percent of the less-changed family's changes, at
        /// least.
        let confidence: Double

        /// The limits `thresholds` set.
        init(_ thresholds: SignalThresholds) {
            let signal = SignalThresholds.hiddenCoupling
            support = thresholds.limit(SignalThresholds.support, of: signal) ?? 0
            confidence = thresholds.limit(SignalThresholds.confidence, of: signal) ?? 0
        }
    }

    /// The rule as reports state it with `thresholds`, before the funnel.
    static func rule(thresholds: SignalThresholds) -> String {
        let limits = Limits(thresholds)
        let support = MarkdownNumber.exact(limits.support)
        let confidence = MarkdownNumber.exact(limits.confidence)
        return "pairs of production families changed together by at least \(support) commits in the window "
            + "(confidence at least \(confidence)%: support ÷ the less-changed family's changes) with no static "
            + "dependency: neither references the other (index: calls, reads, writes, directly or through a "
            + "protocol requirement the other witnesses), they don't share or nest a package type, and neither "
            + "references the other's type or its members; same file or module isn't a dependency; candidates for "
            + "an explicit abstraction"
    }
}

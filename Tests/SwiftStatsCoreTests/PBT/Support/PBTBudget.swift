//
//  PBTBudget.swift
//  SwiftStatsCoreTests
//
//  How much each property test checks and how long it may take. Every
//  property draws `runs(base)` inputs, where `base` is its own count (the
//  engine's 100 unless a comment justifies another), and carries
//  `.timeLimit(PBTBudget.timeLimit)`. `SWIFTSTATS_PBT_SCALE=<n>` multiplies
//  every base count, so a long run keeps the counts' proportions, and the
//  time limit grows with it so a long run doesn't time out on scale alone.
//  The variable changes how much is checked, never what a property means
//  or which inputs it can draw. These are its only readers.
//

import Foundation
import Testing

/// The run count and time limit every property test takes.
enum PBTBudget {
    /// The environment variable that multiplies every base count.
    static let scaleVariable = "SWIFTSTATS_PBT_SCALE"

    /// The largest scale read; a larger one reads as this. Assumed: no long
    /// run goes past ten thousand times the base counts (the design's
    /// longest is 100), and the bound keeps `runs(_:)` and the time limit's
    /// minutes far from overflowing.
    static let maximumScale = 10_000

    /// This process's scale, read once from `SWIFTSTATS_PBT_SCALE`.
    static let scale = scale(from: ProcessInfo.processInfo.environment)

    /// The time limit of every property test at this process's scale.
    static let timeLimit = timeLimit(scale: scale)

    /// The scale `environment` sets: its `SWIFTSTATS_PBT_SCALE` as a whole
    /// number, at most `maximumScale`, including one too large for an `Int`;
    /// unset, not a number or below 1 reads as 1.
    static func scale(from environment: [String: String]) -> Int {
        guard let text = environment[scaleVariable] else {
            return 1
        }
        guard let value = Int(text) else {
            return isPositiveWholeNumber(text) ? maximumScale : 1
        }
        return value < 1 ? 1 : min(value, maximumScale)
    }

    /// Whether `text` is ASCII digits, optionally after a `+`, as `Int(_:)`
    /// reads a positive number: an unparsable one is then too large.
    private static func isPositiveWholeNumber(_ text: String) -> Bool {
        let digits = text.hasPrefix("+") ? text.dropFirst() : Substring(text)
        return digits.isEmpty == false && digits.allSatisfy { ("0"..."9").contains($0) }
    }

    /// The runs a property whose base count is `base` draws at this
    /// process's scale.
    static func runs(_ base: Int) -> Int {
        runs(base, scale: scale)
    }

    /// `base` times `scale`, or `Int.max` where the product would overflow.
    static func runs(_ base: Int, scale: Int) -> Int {
        let (product, overflow) = base.multipliedReportingOverflow(by: scale)
        return overflow ? Int.max : product
    }

    /// The time limit at `scale`: one minute per unit of scale, and never
    /// less than a minute, the shortest limit Swift Testing takes.
    static func timeLimit(scale: Int) -> TimeLimitTrait.Duration {
        .minutes(max(1, scale))
    }
}

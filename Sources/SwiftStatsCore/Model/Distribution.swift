//
//  Distribution.swift
//  SwiftStatsCore
//
//  A summary of one measure over many records (PRD §7.2). Percentiles use
//  nearest-rank (PRD §9), so every field is an integer and repeat runs give
//  identical output. Over no records the order statistics are null, not 0
//  (PRD §6.5: missing is never zero).
//

/// Count, total and nearest-rank percentiles of a list of values.
public struct Distribution: Codable, Hashable, Sendable {
    /// The median's percentile.
    private static let medianPercent = 50
    /// The upper percentile reported.
    private static let upperPercent = 90
    /// Percentages are out of this.
    private static let wholePercent = 100

    /// How many values.
    public let count: Int
    /// Their sum.
    public let total: Int
    /// The smallest; nil when there are none.
    public let min: Int?
    /// The nearest-rank median; nil when there are none.
    public let median: Int?
    /// The nearest-rank 90th percentile; nil when there are none.
    public let p90: Int?
    /// The largest; nil when there are none.
    public let max: Int?

    /// The distribution of `values`.
    public init(_ values: [Int]) {
        let sorted = values.sorted()
        count = sorted.count
        total = sorted.reduce(0, +)
        min = sorted.first
        max = sorted.last
        median = Self.nearestRank(Self.medianPercent, of: sorted)
        p90 = Self.nearestRank(Self.upperPercent, of: sorted)
    }

    /// The nearest-rank `percent`-th percentile of sorted values: the value
    /// at rank ⌈percent/100 × count⌉, 1-based; nil for no values.
    static func nearestRank(_ percent: Int, of sorted: [Int]) -> Int? {
        guard sorted.isEmpty == false else {
            return nil
        }
        let rank = (percent * sorted.count + wholePercent - 1) / wholePercent
        return sorted[Swift.max(rank, 1) - 1]
    }
}

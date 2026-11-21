//
//  CoverageTally.swift
//  SwiftStatsCore
//
//  How many of something coverage ran (M5): lines or regions, covered of
//  total. The percentage is worked out at report time.
//

/// Covered and total lines or regions.
public struct CoverageTally: Codable, Hashable, Sendable {
    /// How many ran at least once.
    public let covered: Int
    /// How many there are.
    public let total: Int

    /// Creates a tally. Fields are documented on their properties.
    public init(covered: Int, total: Int) {
        self.covered = covered
        self.total = total
    }
}

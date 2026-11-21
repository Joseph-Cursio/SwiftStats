//
//  CoverageLineRun.swift
//  SwiftStatsCore
//
//  Consecutive mapped lines of a file that coverage counted alike (M5).
//

/// Consecutive lines with one count.
public struct CoverageLineRun: Codable, Hashable, Sendable {
    /// The first line.
    public let start: Int
    /// The last line, inclusive.
    public let end: Int
    /// Each line's count by llvm-cov's file line rule; `Int64.max` when
    /// saturated.
    public let count: Int64
    /// Whether each line ran but holds a region that didn't (an unrun
    /// branch, closure or autoclosure on a run line).
    public let partlyRun: Bool

    /// Creates a run. Fields are documented on their properties.
    public init(start: Int, end: Int, count: Int64, partlyRun: Bool) {
        self.start = start
        self.end = end
        self.count = count
        self.partlyRun = partlyRun
    }
}

//
//  ComparisonOutcome.swift
//  SwiftStatsCore
//
//  Whether a collector's results can be compared between two snapshots
//  (PRD §6.6).
//

/// How a collector's results stand between two snapshots.
public enum ComparisonOutcome: String, Codable, Hashable, Sendable {
    /// It ran in both with the same build and options.
    case compared
    /// It didn't run in one or both.
    case notCollected = "not-collected"
    /// It ran in both, with a different build, version or options.
    case notComparable = "not-comparable"
}

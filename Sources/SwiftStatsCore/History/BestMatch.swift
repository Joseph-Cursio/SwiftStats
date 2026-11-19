//
//  BestMatch.swift
//  SwiftStatsCore
//
//  The best similar-body candidate seen so far for one family, and whether
//  another candidate scored the same.
//

/// A best candidate.
struct BestMatch {
    /// The candidate's index.
    let index: Int
    /// Its similarity score.
    let score: Double
    /// Whether another candidate scored the same.
    let tied: Bool
}

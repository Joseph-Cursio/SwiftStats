//
//  SignalComputation.swift
//  SwiftStatsCore
//
//  A computed signal before ranking: how many candidates its pool held,
//  what it scored, and the rule a report prints.
//

/// A signal's pool and scores.
struct SignalComputation: Hashable, Sendable {
    /// How membership is decided, as a report states it.
    let rule: String
    /// The size of the signal's pool.
    let candidates: Int
    /// The candidates it lists, in no order.
    let scored: [SignalScore]
}

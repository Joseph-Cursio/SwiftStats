//
//  EffectRun.swift
//  SwiftStatsCore
//
//  What one side-effect run produced: facts for the records it joined, and
//  the run's own outputs.
//

/// The results of one side-effect run.
struct EffectRun {
    /// Each joined record's facts, by record key.
    let facts: [String: EffectFacts]
    /// The run's revision, pass count and refuted types.
    let summary: EffectSummary
}

//
//  StoredFunctionFacts.swift
//  SwiftStatsCore
//
//  What store v3 (M4) adds to a function row: whether its file is
//  generated and its side-effect columns. A row written before v3 has
//  none of them, which a nil group says without optional Booleans.
//

/// The columns store v3 adds to a function row.
public struct StoredFunctionFacts: Hashable, Sendable {
    /// Whether the record's file is generated (`generated`, PRD D8).
    public let generated: Bool
    /// Its side-effect columns; nil for a record with no effect facts: a
    /// test, an initializer, or a scan where SwiftEffectInference didn't run.
    public let effect: StoredEffect?
}

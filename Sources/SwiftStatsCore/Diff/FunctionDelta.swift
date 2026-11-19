//
//  FunctionDelta.swift
//  SwiftStatsCore
//
//  A matched function record whose metrics changed (PRD §6.6).
//

/// The changed metrics of one function record.
public struct FunctionDelta: Codable, Hashable, Sendable {
    /// The record's key in the newer snapshot.
    public let key: String
    /// Its changed metrics, sorted by name.
    public let metrics: [MetricDelta]
}

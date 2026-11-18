//
//  CollectorState.swift
//  SwiftStatsCore
//
//  How a collector's run went (PRD §6.5).
//

/// How a collector's run went.
public enum CollectorState: String, Codable, CaseIterable, Sendable {
    /// It ran and failed; the reason gives the exit status and output.
    case failed
    /// It ran and its results are in the report.
    case ran
    /// It didn't run; the reason says why. Its metrics are absent, not zero.
    case skipped
}

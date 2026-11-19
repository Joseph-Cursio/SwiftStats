//
//  DeltaVerdict.swift
//  SwiftStatsCore
//
//  Whether a metric's change is good news (PRD §6.6).
//

/// How a delta reads.
public enum DeltaVerdict: String, Codable, Hashable, Sendable {
    /// It got better.
    case better
    /// Neither, or no direction applies.
    case neutral
    /// It got worse.
    case worse
}

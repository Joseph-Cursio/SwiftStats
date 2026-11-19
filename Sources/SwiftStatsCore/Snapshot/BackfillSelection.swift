//
//  BackfillSelection.swift
//  SwiftStatsCore
//
//  Which first-parent commits a backfill picks (PRD §7.13).
//

/// Which first-parent commits a backfill picks.
public enum BackfillSelection: Sendable {
    /// Every Nth commit, counting from the root (position 0).
    case every(Int)
    /// The latest commit of each ISO week, in UTC.
    case weekly
}

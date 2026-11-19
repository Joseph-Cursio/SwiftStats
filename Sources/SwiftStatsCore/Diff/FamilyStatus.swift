//
//  FamilyStatus.swift
//  SwiftStatsCore
//
//  What happened to a function family between two snapshots (PRD §6.6).
//

/// One thing that changed about a function family.
public enum FamilyStatus: String, Codable, Hashable, Sendable, Comparable {
    /// Its key became or stopped being file-scoped (`private`/`fileprivate`).
    case accessChanged = "access-changed"
    /// It is new.
    case added
    /// A record's body changed, or a nested record came or went.
    case changed
    /// Its file changed.
    case moved
    /// It is gone.
    case removed
    /// Its key changed other than in the file-scoped part.
    case renamed

    /// Orders statuses by name, for stable output.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

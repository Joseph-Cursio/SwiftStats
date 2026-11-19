//
//  FamilyChange.swift
//  SwiftStatsCore
//
//  One function family that changed between two snapshots (PRD §6.6).
//

/// A function family that was added, removed, or matched and changed.
public struct FamilyChange: Codable, Hashable, Sendable {
    /// The family's key in the newer snapshot, or in the older one when removed.
    public let key: String
    /// What happened, sorted.
    public let statuses: [FamilyStatus]
    /// Its key in the older snapshot; nil when added.
    public let oldKey: String?
    /// Its file in the older snapshot; nil when added.
    public let oldFile: String?
    /// Its file in the newer snapshot; nil when removed.
    public let newFile: String?
    /// How it was matched; nil when added or removed.
    public let matchedBy: MatchMethod?
    /// Every record in the family, by key (the older snapshot's when removed).
    public let records: [String]
    /// The records whose body changed or that came or went, by key.
    public let changedRecords: [String]
}

//
//  FamilyChange.swift
//  SwiftStatsCore
//
//  One function family that changed between two snapshots (PRD §6.6), with
//  the records whose primary USR changed under the same key when the index
//  compares (M7, design §10.3).
//

/// A function family that was added, removed, or matched and changed.
public struct FamilyChange: Codable, Hashable, Sendable {
    /// The keys the diff JSON writes.
    private enum CodingKeys: String, CodingKey {
        case key
        case statuses
        case oldKey
        case oldFile
        case newFile
        case matchedBy
        case records
        case changedRecords
        case usrChanges
    }

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
    /// The matched records that kept their key but not their primary USR,
    /// sorted by key: empty unless the index compares; left out of the
    /// JSON when empty.
    public let usrChanges: [USRChange]

    /// Creates a change. Fields are documented on their properties.
    init(
        key: String,
        statuses: [FamilyStatus],
        oldKey: String?,
        oldFile: String?,
        newFile: String?,
        matchedBy: MatchMethod?,
        records: [String],
        changedRecords: [String],
        usrChanges: [USRChange]
    ) {
        self.key = key
        self.statuses = statuses
        self.oldKey = oldKey
        self.oldFile = oldFile
        self.newFile = newFile
        self.matchedBy = matchedBy
        self.records = records
        self.changedRecords = changedRecords
        self.usrChanges = usrChanges
    }

    /// Reads a change; one without `usrChanges` has none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            key: container.decode(String.self, forKey: .key),
            statuses: container.decode([FamilyStatus].self, forKey: .statuses),
            oldKey: container.decodeIfPresent(String.self, forKey: .oldKey),
            oldFile: container.decodeIfPresent(String.self, forKey: .oldFile),
            newFile: container.decodeIfPresent(String.self, forKey: .newFile),
            matchedBy: container.decodeIfPresent(MatchMethod.self, forKey: .matchedBy),
            records: container.decode([String].self, forKey: .records),
            changedRecords: container.decode([String].self, forKey: .changedRecords),
            usrChanges: container.decodeIfPresent([USRChange].self, forKey: .usrChanges) ?? []
        )
    }

    /// Writes the change, leaving out what it doesn't have.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(statuses, forKey: .statuses)
        try container.encodeIfPresent(oldKey, forKey: .oldKey)
        try container.encodeIfPresent(oldFile, forKey: .oldFile)
        try container.encodeIfPresent(newFile, forKey: .newFile)
        try container.encodeIfPresent(matchedBy, forKey: .matchedBy)
        try container.encode(records, forKey: .records)
        try container.encode(changedRecords, forKey: .changedRecords)
        if usrChanges.isEmpty == false {
            try container.encode(usrChanges, forKey: .usrChanges)
        }
    }
}

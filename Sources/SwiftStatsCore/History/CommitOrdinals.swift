//
//  CommitOrdinals.swift
//  SwiftStatsCore
//
//  The commits that changed one family, as positions in its history's
//  commit log, written as a bare JSON array. `FamilyHistory.changedBy`
//  has three states, as `allChanges` does: nil for a family with no
//  history (uncommitted, which `HistoryChain` calls "no history, not an
//  empty one"), an empty list for a traced family no logged commit
//  changed, and the ordinals otherwise. Naming the list states that once,
//  here, instead of leaving it to an optional array whose nil and empty
//  readers must be told apart at every use.
//

/// The commits that changed a family, as indices into `HistoryReport.commitLog`.
public struct CommitOrdinals: Codable, Hashable, Sendable {
    /// The indices, from 0, in walk order: newest first.
    public let ordinals: [Int]

    /// Wraps `ordinals`.
    public init(_ ordinals: [Int]) {
        self.ordinals = ordinals
    }

    /// Reads a bare array.
    public init(from decoder: any Decoder) throws {
        ordinals = try decoder.singleValueContainer().decode([Int].self)
    }

    /// Writes a bare array.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(ordinals)
    }
}

//
//  MutationSource.swift
//  SwiftStatsCore
//
//  An earlier snapshot mutation results came from (M6, design §3, §5): a
//  `--since` merge's base, or the snapshot a run's rows were carried from.
//

/// An earlier snapshot results came from.
public struct MutationSource: Codable, Hashable, Sendable {
    /// Its commit.
    public let commit: String
    /// When its mutation results were collected.
    public let collectedAt: String

    /// Creates a source. Fields are documented on their properties.
    public init(commit: String, collectedAt: String) {
        self.commit = commit
        self.collectedAt = collectedAt
    }
}

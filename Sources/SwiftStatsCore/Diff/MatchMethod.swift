//
//  MatchMethod.swift
//  SwiftStatsCore
//
//  How two function families were matched (PRD §6.6, §7.13), so a guessed
//  rename can be told from a certain one.
//

/// How a family in one snapshot was matched to one in the other.
public enum MatchMethod: String, Codable, Hashable, Sendable {
    /// The same unique, non-trivial body hash.
    case bodyHash = "body-hash"
    /// The same key apart from its file-scoped part and location suffixes.
    case fileScopedKey = "file-scoped-key"
    /// The same key.
    case key
}

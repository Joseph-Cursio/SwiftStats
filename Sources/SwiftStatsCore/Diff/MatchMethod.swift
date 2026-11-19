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
    /// History only: the same key apart from its module and file-scoped
    /// part, after the file moved to another target.
    case moduleMovedKey = "module-moved-key"
    /// History only: the same name, kind, file and enclosing type, held by
    /// one family on each side: a signature change.
    case sameName = "same-name"
    /// History only: bodies of three lines or more sharing at least 70% of
    /// their lines, each the other's only best match: a guess.
    case similarBody = "similar-body"

    /// The methods from the most certain to the least.
    private static let certaintyOrder: [Self] = [
        .key, .fileScopedKey, .moduleMovedKey, .bodyHash, .sameName, .similarBody
    ]

    /// How sure the match is, most certain first: a lineage keeps its
    /// weakest link (PRD §7.13).
    var uncertainty: Int {
        Self.certaintyOrder.firstIndex(of: self) ?? Self.certaintyOrder.count
    }
}

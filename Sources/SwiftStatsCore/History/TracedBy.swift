//
//  TracedBy.swift
//  SwiftStatsCore
//
//  How a family's history was traced back: the weakest link of its lineage.
//

/// How a family's history was traced back.
public enum TracedBy: String, Codable, Hashable, Sendable {
    /// The weakest link was a unique body hash.
    case bodyHash = "body-hash"
    /// The weakest link was the same key apart from its file-scoped part.
    case fileScopedKey = "file-scoped-key"
    /// Every link had the same key.
    case key
    /// The weakest link was a move to another target.
    case moduleMovedKey = "module-moved-key"
    /// The weakest link was a signature change matched by name.
    case sameName = "same-name"
    /// The weakest link was a similar body: a guess.
    case similarBody = "similar-body"
    /// The family exists only in uncommitted changes, so it has no history.
    case uncommitted

    /// The tracing that a link of `method` makes.
    init(_ method: MatchMethod) {
        switch method {
        case .bodyHash:
            self = .bodyHash

        case .fileScopedKey:
            self = .fileScopedKey

        case .key:
            self = .key

        case .moduleMovedKey:
            self = .moduleMovedKey

        case .sameName:
            self = .sameName

        case .similarBody:
            self = .similarBody
        }
    }
}

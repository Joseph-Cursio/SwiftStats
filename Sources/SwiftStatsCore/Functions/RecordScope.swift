//
//  RecordScope.swift
//  SwiftStatsCore
//
//  A record's body on the collector's stack. Declarations inside it take the
//  record's key as their prefix (PRD §6.1). A context, such as a stored
//  property's initialiser, works the same way for keys but is not a record,
//  so it is never anyone's parent.
//

import SwiftSyntax

/// A record's body.
struct RecordScope {
    /// The node that opened the scope.
    let owner: SyntaxIdentifier
    /// The enclosing record's key.
    let key: String
    /// How many `#if` conditions were open when the record began; conditions
    /// opened inside it belong to the nested declarations' keys.
    let conditionDepth: Int
    /// Whether the scope is a record (and so the parent of what it holds),
    /// as opposed to a context that only prefixes keys.
    let isRecord: Bool
}

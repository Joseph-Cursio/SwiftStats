//
//  RecordDraft.swift
//  SwiftStatsCore
//
//  Everything the collector knows about a declaration before the stack turns
//  its declaration text into a key.
//

import SwiftSyntax

/// A record before its key is assembled.
struct RecordDraft {
    /// The record kind.
    let kind: FunctionKind
    /// The declared name.
    let name: String
    /// The accessor keyword, for accessors.
    let accessorKind: String?
    /// The declaration text (PRD §6.1), from `DeclarationRenderer`.
    let declaration: String
    /// Whether the declaration itself is `private` or `fileprivate`.
    let isFileScoped: Bool
    /// The node whose range the record covers and whose lines are counted.
    let node: Syntax
    /// Tokens before this position are not counted (the attributes).
    let countFrom: AbsolutePosition
    /// The token stream the body hash is taken over.
    let bodyTokens: String
    /// The record's role.
    let role: CodeRole
}

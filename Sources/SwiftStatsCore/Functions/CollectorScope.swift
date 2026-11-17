//
//  CollectorScope.swift
//  SwiftStatsCore
//
//  One level of nesting while walking a file: a type (or extension) or a
//  record. Records nest when a function is declared inside another function,
//  or when a subscript has explicit accessors.
//

import SwiftSyntax

/// A level of nesting on the collector's stack.
enum CollectorScope {
    /// A record's body.
    case record(RecordScope)
    /// A type or extension body.
    case type(TypeScope)

    /// The node that opened this scope, so the matching `visitPost` can
    /// close it.
    var owner: SyntaxIdentifier {
        switch self {
        case .record(let scope):
            return scope.owner

        case .type(let scope):
            return scope.owner
        }
    }
}

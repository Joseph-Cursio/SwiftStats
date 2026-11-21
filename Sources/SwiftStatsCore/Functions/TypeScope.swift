//
//  TypeScope.swift
//  SwiftStatsCore
//
//  A type or extension body on the collector's stack.
//

import SwiftSyntax

/// A type or extension body.
struct TypeScope {
    /// The node that opened the scope.
    let owner: SyntaxIdentifier
    /// The path component: the type's name, or for an extension the extended
    /// type and any `where` clause.
    let pathComponent: String
    /// The type's name, or for an extension the extended type as written,
    /// without the `where` clause: its part of a record's type path.
    let typeName: String
    /// The bare type name, used to recognise `XCTestCase` subclasses.
    let simpleName: String
    /// Whether the type or extension is `private` or `fileprivate`, which
    /// scopes its members to the file.
    let isFileScoped: Bool
}

//
//  APIDeclaration.swift
//  SwiftStatsCore
//
//  One declaration counted for the API surface (PRD §7.5).
//

/// A declaration with an access level.
struct APIDeclaration: Hashable {
    /// The module it is in.
    let module: String
    /// Its effective access level: what it writes or inherits from its
    /// extension, capped by the declarations around it.
    let access: AccessLevel
    /// Whether it gets `internal` by default: no access modifier of its own
    /// or on its extension, and nothing around it lowers that.
    let isImplicitlyInternal: Bool
    /// Whether it has a doc comment.
    let isDocumented: Bool
    /// Whether it is a class.
    let isClass: Bool
    /// Whether it is a `final` class.
    let isFinalClass: Bool
}

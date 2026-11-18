//
//  APISurface.swift
//  SwiftStatsCore
//
//  A module's or project's API surface (PRD §7.5).
//

/// Declarations by access level, with documentation, `final` and
/// over-exposure counts.
public struct APISurface: Codable, Hashable, Sendable {
    /// Declarations by effective access level (`private` … `open`): types,
    /// typealiases, functions, initialisers, subscripts and each name a
    /// `var` or `let` binds, outside function bodies.
    public let accessLevels: [String: Int]
    /// Declarations that are `internal` by default, with no modifier of
    /// their own or on their extension.
    public let implicitlyInternal: Int
    /// Declarations whose effective level is `public` or `open`.
    public let publicDeclarations: Int
    /// Of those, the ones with a doc comment.
    public let documentedPublicDeclarations: Int
    /// Classes, local ones excluded.
    public let classes: Int
    /// Of those, the `final` ones.
    public let finalClasses: Int
    /// SwiftProjectLint's `couldBePrivate`, `couldBePrivateMember` and
    /// `protocolCouldBePrivate` findings; nil when it didn't run.
    public let overExposed: Int?

    /// The surface of `declarations`, with `overExposed` from SwiftProjectLint.
    init(_ declarations: [APIDeclaration], overExposed: Int?) {
        let visible = declarations.filter { $0.access >= .public }
        let classDeclarations = declarations.filter(\.isClass)
        accessLevels = declarations.reduce(into: [:]) { counts, declaration in
            counts[declaration.access.name, default: 0] += 1
        }
        implicitlyInternal = declarations.filter(\.isImplicitlyInternal).count
        publicDeclarations = visible.count
        documentedPublicDeclarations = visible.filter(\.isDocumented).count
        classes = classDeclarations.count
        finalClasses = classDeclarations.filter(\.isFinalClass).count
        self.overExposed = overExposed
    }
}

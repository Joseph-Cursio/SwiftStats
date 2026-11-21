//
//  FunctionFinder.swift
//  SwiftStatsCore
//
//  Every function, initialiser and typealias declaration in a tree, and
//  every type declared `@Suite` (`SwiftTestingIdentity`), nested ones
//  included.
//

import SwiftSyntax

/// Collects every function, initialiser and typealias declaration in a
/// tree, and every `@Suite` type.
final class FunctionFinder: SyntaxVisitor {
    /// The function declarations found, in source order.
    var found: [FunctionDeclSyntax] = []
    /// The initialiser declarations found, in source order.
    var initializers: [InitializerDeclSyntax] = []
    /// The typealias declarations found, in source order.
    var aliases: [TypeAliasDeclSyntax] = []
    /// The path and tags of each `@Suite` type found, in source order.
    var suites: [(path: [String], tags: Set<String>)] = []

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        found.append(node)
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        initializers.append(node)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        addSuite(Syntax(node))
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        addSuite(Syntax(node))
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        addSuite(Syntax(node))
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        addSuite(Syntax(node))
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        aliases.append(node)
        return .visitChildren
    }

    /// Adds the type `node` declares when it is a `@Suite`, and goes on
    /// into its members.
    private func addSuite(_ node: Syntax) -> SyntaxVisitorContinueKind {
        if let suite = SwiftTestingIdentity.suite(node) {
            suites.append(suite)
        }
        return .visitChildren
    }

    deinit {
        // Nothing to release beyond the found declarations.
    }
}

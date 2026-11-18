//
//  FunctionFinder.swift
//  SwiftStatsCore
//
//  Every function declaration in a tree, nested ones included.
//

import SwiftSyntax

/// Collects every function declaration in a tree.
final class FunctionFinder: SyntaxVisitor {
    /// The declarations found, in source order.
    var found: [FunctionDeclSyntax] = []

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        found.append(node)
        return .visitChildren
    }

    deinit {
        // Nothing to release beyond the found declarations.
    }
}

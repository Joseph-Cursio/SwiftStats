//
//  DeclarationFacts.swift
//  SwiftStatsCore
//
//  Small facts about a record's declaration (PRD §7.2): its parameter count
//  and whether it is documented.
//

import SwiftSyntax

/// Reads a record's parameter count and doc comment.
enum DeclarationFacts {
    /// Parameters in the declaration's own list, for `func`, `init` and
    /// `subscript`; nil for every other node.
    static func parameterCount(of node: Syntax) -> Int? {
        if let function = node.as(FunctionDeclSyntax.self) {
            return function.signature.parameterClause.parameters.count
        }
        if let initializer = node.as(InitializerDeclSyntax.self) {
            return initializer.signature.parameterClause.parameters.count
        }
        if let subscriptDecl = node.as(SubscriptDeclSyntax.self) {
            return subscriptDecl.parameterClause.parameters.count
        }
        return nil
    }

    /// Whether the declaration has a doc comment. An accessor, or the
    /// implicit getter's accessor block, takes the property or subscript it
    /// belongs to.
    static func isDocumented(_ node: Syntax) -> Bool {
        hasDocComment(documentedDeclaration(of: node)?.leadingTrivia ?? [])
    }

    /// The declaration a doc comment for `node` would be written on.
    private static func documentedDeclaration(of node: Syntax) -> Syntax? {
        guard node.is(AccessorDeclSyntax.self) || node.is(AccessorBlockSyntax.self) else {
            return node
        }
        var current = node.parent
        while let ancestor = current {
            if ancestor.is(VariableDeclSyntax.self) || ancestor.is(SubscriptDeclSyntax.self) {
                return ancestor
            }
            current = ancestor.parent
        }
        return nil
    }

    /// Whether `trivia` holds a `///` or `/** */` comment.
    private static func hasDocComment(_ trivia: Trivia) -> Bool {
        trivia.contains { piece in
            switch piece {
            case .docBlockComment, .docLineComment:
                return true

            default:
                return false
            }
        }
    }
}

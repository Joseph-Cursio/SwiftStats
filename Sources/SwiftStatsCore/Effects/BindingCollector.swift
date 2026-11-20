//
//  BindingCollector.swift
//  SwiftStatsCore
//
//  The names a function body binds: `let` and `var` patterns, loop and
//  `case` patterns, optional bindings, closure parameters and local
//  functions with their parameters. Scope is ignored, so a name bound
//  anywhere in the body counts as local everywhere in it.
//

import SwiftSyntax

/// Collects the names bound in one body.
final class BindingCollector: SyntaxVisitor {
    /// The names found so far.
    private(set) var names: Set<String> = []

    /// Creates a collector.
    init() {
        super.init(viewMode: .sourceAccurate)
    }

    /// The names bound anywhere in `body`.
    static func names(in body: some SyntaxProtocol) -> Set<String> {
        let collector = Self()
        collector.walk(body)
        return collector.names
    }

    override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
        names.insert(node.identifier.text)
        return .visitChildren
    }

    override func visit(_ node: ClosureShorthandParameterSyntax) -> SyntaxVisitorContinueKind {
        names.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ClosureParameterSyntax) -> SyntaxVisitorContinueKind {
        names.insert((node.secondName ?? node.firstName).text)
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        names.insert(node.name.text)
        for parameter in node.signature.parameterClause.parameters {
            names.insert((parameter.secondName ?? parameter.firstName).text)
        }
        return .visitChildren
    }

    deinit {
        // Nothing to release beyond stored properties.
    }
}

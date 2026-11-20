//
//  EffectSiteCollector.swift
//  SwiftStatsCore
//
//  Finds the declarations of one file that get side-effect facts: every
//  `func` with a body, every computed property's getter and every
//  `subscript` with a body. Setters, observers, a subscript's own accessors,
//  initialisers and deinitialisers get none (PRD §7.10).
//

import SwiftSyntax

/// Collects the effect sites of one file, in source order.
final class EffectSiteCollector: SyntaxVisitor {
    /// The sites found so far.
    private(set) var sites: [EffectSite] = []

    /// Creates a collector.
    init() {
        super.init(viewMode: .sourceAccurate)
    }

    /// The effect sites of `tree`.
    static func sites(in tree: SourceFileSyntax) -> [EffectSite] {
        let collector = Self()
        collector.walk(tree)
        return collector.sites
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.body != nil {
            sites.append(.function(node))
        }
        return .visitChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        if let block = node.accessorBlock, FunctionCollector.hasBody(block) {
            sites.append(.subscriptDeclaration(node, block: block))
        }
        return .visitChildren
    }

    override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
        guard let binding = node.parent?.as(PatternBindingSyntax.self),
              let variable = FunctionCollector.variable(of: binding) else {
            return .visitChildren
        }
        switch node.accessors {
        case .getter:
            sites.append(.getter(variable, block: node, start: Syntax(node)))

        case .accessors(let accessors):
            let getter = accessors.first { $0.accessorSpecifier.tokenKind == .keyword(.get) && $0.body != nil }
            if let getter {
                sites.append(.getter(variable, block: node, start: Syntax(getter)))
            }
        }
        return .visitChildren
    }

    deinit {
        // Nothing to release beyond stored properties.
    }
}

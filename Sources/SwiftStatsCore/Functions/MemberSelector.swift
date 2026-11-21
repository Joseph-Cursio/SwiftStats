//
//  MemberSelector.swift
//  SwiftStatsCore
//
//  What a type's member record is, in the form protocol requirements are
//  matched in (M5, tests per public function): `[static ]name(label:…)`
//  for a function (`_` for a parameter with no label), `[static ]op` for an
//  operator, whose labels Swift ignores, `[static ]name` for a property's
//  accessors and `subscript(label:…)` for a subscript and its accessors.
//  Initialisers and deinitialisers witness none of the requirements the
//  link rule knows, so they get none.
//

import SwiftSyntax

/// Selectors of member records.
enum MemberSelector {
    /// The selector of the record `node` opens; nil for an initialiser, a
    /// deinitialiser or top-level code.
    static func selector(of node: Syntax) -> String? {
        if let function = node.as(FunctionDeclSyntax.self) {
            let head = DeclarationRenderer.typeLevelPrefix(function.modifiers) + function.name.text
            if case .identifier = function.name.tokenKind {
                let labels = function.signature.parameterClause.parameters.map { $0.firstName.text + ":" }
                return head + "(" + labels.joined() + ")"
            }
            return head
        }
        if let subscriptDecl = node.as(SubscriptDeclSyntax.self) {
            return selector(of: subscriptDecl)
        }
        if let block = node.as(AccessorBlockSyntax.self) {
            return block.parent?.as(PatternBindingSyntax.self).map(selector(of:))
        }
        guard let owner = node.as(AccessorDeclSyntax.self)?.parent?.parent?.parent else {
            return nil
        }
        if let subscriptDecl = owner.as(SubscriptDeclSyntax.self) {
            return selector(of: subscriptDecl)
        }
        return owner.as(PatternBindingSyntax.self).map(selector(of:))
    }

    /// `[static ]subscript(label:…)`: a subscript parameter has an external
    /// label only when it is written with two names.
    private static func selector(of node: SubscriptDeclSyntax) -> String {
        let labels = node.parameterClause.parameters.map { parameter in
            (parameter.secondName == nil ? "_" : parameter.firstName.text) + ":"
        }
        return DeclarationRenderer.typeLevelPrefix(node.modifiers) + "subscript(" + labels.joined() + ")"
    }

    /// `[static ]name`, for a property's accessors.
    private static func selector(of binding: PatternBindingSyntax) -> String {
        let modifiers = FunctionCollector.variable(of: binding)?.modifiers
        return (modifiers.map(DeclarationRenderer.typeLevelPrefix) ?? "") + CanonicalText.render(binding.pattern)
    }
}

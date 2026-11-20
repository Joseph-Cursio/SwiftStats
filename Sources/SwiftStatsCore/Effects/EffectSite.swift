//
//  EffectSite.swift
//  SwiftStatsCore
//
//  A declaration that gets side-effect facts, with the node its record
//  starts at (PRD §7.10): a `func`; the getter of a computed property, which
//  takes the property's declared tier and its accessor block's purity; or a
//  `subscript`, which takes its accessor block's purity.
//

import SwiftSyntax

/// One declaration side-effect facts are computed for.
enum EffectSite {
    /// A `func` with a body.
    case function(FunctionDeclSyntax)
    /// A computed property's getter: the property, its accessor block, and
    /// where the getter's record starts (the block for an implicit getter,
    /// the `get` accessor otherwise).
    case getter(VariableDeclSyntax, block: AccessorBlockSyntax, start: Syntax)
    /// A `subscript` whose accessor block has a body.
    case subscriptDeclaration(SubscriptDeclSyntax, block: AccessorBlockSyntax)

    /// Where the site's record starts.
    var start: Syntax {
        switch self {
        case .function(let function):
            return Syntax(function)

        case .getter(_, _, let start):
            return start

        case .subscriptDeclaration(let declaration, _):
            return Syntax(declaration)
        }
    }

    /// The kind of the site's record.
    var kind: FunctionKind {
        switch self {
        case .function:
            return .function

        case .getter:
            return .accessor

        case .subscriptDeclaration:
            return .subscriptDeclaration
        }
    }
}

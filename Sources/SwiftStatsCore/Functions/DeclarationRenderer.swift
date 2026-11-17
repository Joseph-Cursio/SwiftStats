//
//  DeclarationRenderer.swift
//  SwiftStatsCore
//
//  Renders the declaration part of a function key (PRD §6.1): everything
//  Swift lets overloads differ by — `static`/`class`, operator fixity, name,
//  generic signature and constraints, external labels and parameter types,
//  effects and return type — and nothing they can't, such as internal
//  parameter names, default values or the body.
//

import SwiftSyntax

/// Builds the declaration text that identifies a function among its siblings.
enum DeclarationRenderer {
    /// `[static ][prefix ]func name<T>(label: Type) async throws -> R where …`
    static func function(_ node: FunctionDeclSyntax) -> String {
        let parameters = node.signature.parameterClause.parameters.map { parameter in
            Self.parameter(label: parameter.firstName.text, type: parameter.type, ellipsis: parameter.ellipsis)
        }
        let head = typeLevelPrefix(node.modifiers) + fixityPrefix(node.modifiers) + "func " + node.name.text
        return join(
            head + generics(node.genericParameterClause) + "(" + parameters.joined(separator: ", ") + ")",
            node.signature.effectSpecifiers.map(CanonicalText.render),
            node.signature.returnClause.map(CanonicalText.render),
            node.genericWhereClause.map(CanonicalText.render)
        )
    }

    /// `init[?]<T>(label: Type) async throws where …`
    static func initializer(_ node: InitializerDeclSyntax) -> String {
        let parameters = node.signature.parameterClause.parameters.map { parameter in
            Self.parameter(label: parameter.firstName.text, type: parameter.type, ellipsis: parameter.ellipsis)
        }
        let head = "init" + (node.optionalMark?.text ?? "")
        return join(
            head + generics(node.genericParameterClause) + "(" + parameters.joined(separator: ", ") + ")",
            node.signature.effectSpecifiers.map(CanonicalText.render),
            node.genericWhereClause.map(CanonicalText.render)
        )
    }

    /// `[static ]subscript<T>(_: Int) -> R where …`. A subscript parameter has
    /// an external label only when it is written with two names.
    static func subscriptDeclaration(_ node: SubscriptDeclSyntax) -> String {
        let parameters = node.parameterClause.parameters.map { parameter in
            let label = parameter.secondName == nil ? "_" : parameter.firstName.text
            return Self.parameter(label: label, type: parameter.type, ellipsis: parameter.ellipsis)
        }
        return join(
            typeLevelPrefix(node.modifiers) + "subscript" + generics(node.genericParameterClause)
                + "(" + parameters.joined(separator: ", ") + ")",
            CanonicalText.render(node.returnClause),
            node.genericWhereClause.map(CanonicalText.render)
        )
    }

    /// `[static ]var name[: Type]`: the property an accessor belongs to.
    static func property(_ binding: PatternBindingSyntax, modifiers: DeclModifierListSyntax?) -> String {
        let prefix = modifiers.map(typeLevelPrefix) ?? ""
        let name = CanonicalText.render(binding.pattern)
        let type = binding.typeAnnotation.map { ": " + CanonicalText.render($0.type) } ?? ""
        return prefix + "var " + name + type
    }

    /// `<owner> { <accessor> }`, for example `var count: Int { get }`.
    static func accessor(owner: String, kind: String) -> String {
        owner.isEmpty ? "{ \(kind) }" : "\(owner) { \(kind) }"
    }

    /// `static ` or `class ` when the declaration is type-level.
    static func typeLevelPrefix(_ modifiers: DeclModifierListSyntax) -> String {
        if modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) {
            return "static "
        }
        if modifiers.contains(where: { $0.name.tokenKind == .keyword(.class) }) {
            return "class "
        }
        return ""
    }

    /// `prefix `, `postfix ` or `infix ` for operator functions.
    private static func fixityPrefix(_ modifiers: DeclModifierListSyntax) -> String {
        let fixities: [(keyword: Keyword, text: String)] = [
            (.prefix, "prefix"), (.postfix, "postfix"), (.infix, "infix")
        ]
        for fixity in fixities where modifiers.contains(where: { $0.name.tokenKind == .keyword(fixity.keyword) }) {
            return fixity.text + " "
        }
        return ""
    }

    /// `label: Type` or `label: Type...`.
    private static func parameter(label: String, type: TypeSyntax, ellipsis: TokenSyntax?) -> String {
        label + ": " + CanonicalText.render(type) + (ellipsis == nil ? "" : "...")
    }

    /// The canonical generic parameter clause, or nothing.
    private static func generics(_ clause: GenericParameterClauseSyntax?) -> String {
        clause.map(CanonicalText.render) ?? ""
    }

    /// The non-nil, non-empty parts joined by spaces.
    private static func join(_ parts: String?...) -> String {
        parts.compactMap(\.self).filter { $0.isEmpty == false }.joined(separator: " ")
    }
}

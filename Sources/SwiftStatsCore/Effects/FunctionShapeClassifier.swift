//
//  FunctionShapeClassifier.swift
//  SwiftStatsCore
//
//  The algebraic shape of a value-shaped function (PRD §7.10), the shapes a
//  property-based template could test: an endomorphism, a binary operation,
//  a method returning its own type, or a predicate. Types are compared as
//  written, without whitespace, reading `Self` as the enclosing type.
//

import SwiftSyntax

/// Classifies a value-shaped function by its signature.
enum FunctionShapeClassifier {
    /// Parameters of a binary operation, and at most those of a predicate.
    private static let binaryArity = 2

    /// The first shape `function` has, or nil: always nil for an `override`
    /// or a function without parameters.
    static func shape(of function: FunctionDeclSyntax) -> EffectFacts.Shape? {
        let parameters = function.signature.parameterClause.parameters
        guard let returnClause = function.signature.returnClause,
              parameters.isEmpty == false,
              hasModifier(.override, in: function.modifiers) == false else {
            return nil
        }
        let enclosing = enclosingType(of: function)
        let returned = normalized(returnClause.type, enclosing: enclosing)
        let types = parameters.map { parameter in
            normalized(parameter.type, enclosing: enclosing) + (parameter.ellipsis == nil ? "" : "...")
        }
        if types.count == 1, types[0] == returned {
            return .endomorphism
        }
        if types.count == binaryArity, types.allSatisfy({ $0 == returned }) {
            return .binary
        }
        let isInstanceMethod = hasModifier(.static, in: function.modifiers) == false
            && hasModifier(.class, in: function.modifiers) == false
        if let enclosing, isInstanceMethod, names(returned, enclosing) {
            return .selfReturning
        }
        if types.count <= binaryArity, Set(types).count == 1, returned == "Bool" {
            return .predicate
        }
        return nil
    }

    /// `type`'s text without whitespace, with `Self` read as `enclosing`.
    private static func normalized(_ type: TypeSyntax, enclosing: String?) -> String {
        let text = ValueShapeAnalyzer.compactText(type)
        if text == "Self", let enclosing {
            return enclosing
        }
        return text
    }

    /// Whether `type` names `enclosing`: the same text, its last component
    /// (`Inner` in `extension Outer.Inner`), or either with generic
    /// arguments (`Stack<Element>` in `struct Stack<Element>`).
    private static func names(_ type: String, _ enclosing: String) -> Bool {
        let base = type.split(separator: "<").first.map(String.init) ?? type
        let last = enclosing.split(separator: ".").last.map(String.init) ?? enclosing
        return [type, base].contains { $0 == enclosing || $0 == last }
    }

    /// The type `function` is a member of, as written: the type's name or
    /// the extended type. Nil for a global or local function.
    private static func enclosingType(of function: FunctionDeclSyntax) -> String? {
        var current = function.parent
        while let node = current {
            if let structure = node.as(StructDeclSyntax.self) {
                return structure.name.text
            }
            if let classDeclaration = node.as(ClassDeclSyntax.self) {
                return classDeclaration.name.text
            }
            if let enumeration = node.as(EnumDeclSyntax.self) {
                return enumeration.name.text
            }
            if let actor = node.as(ActorDeclSyntax.self) {
                return actor.name.text
            }
            if let protocolDeclaration = node.as(ProtocolDeclSyntax.self) {
                return protocolDeclaration.name.text
            }
            if let extensionDeclaration = node.as(ExtensionDeclSyntax.self) {
                return ValueShapeAnalyzer.compactText(extensionDeclaration.extendedType)
            }
            if node.is(CodeBlockSyntax.self) || node.is(ClosureExprSyntax.self) || node.is(AccessorBlockSyntax.self) {
                return nil
            }
            current = node.parent
        }
        return nil
    }

    /// Whether `modifiers` contain `keyword`.
    private static func hasModifier(_ keyword: Keyword, in modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { $0.name.tokenKind == .keyword(keyword) }
    }
}

//
//  LawWitnesses.swift
//  SwiftStatsCore
//
//  Finds the witnesses a type or extension writes for the laws the kit
//  tests (PRD §7.11), which make a conformance `custom` rather than
//  synthesised: `==`, `<`, `hash(into:)`, `hashValue`, `encode(to:)` and
//  `init(from:)` taking only an `Encoder` or `Decoder`, `CodingKeys`,
//  `init(rawValue:)`, `rawValue`, `allCases`. Swift also finds an `==` or
//  `<` declared at file scope as the witness of its parameters' type, where
//  the conformance can see it.
//

import SwiftSyntax

/// Reads the witnesses in a member block.
enum LawWitnesses {
    /// How many parameters an `==` or `<` takes.
    private static let operatorArity = 2

    /// The witnesses declared directly in `members`, `#if` branches included.
    static func witnesses(in members: MemberBlockItemListSyntax) -> Set<LawFileFacts.Witness> {
        members.reduce(into: []) { result, item in
            result.formUnion(witnesses(of: item.decl))
        }
    }

    /// The witness a file-scope function is: an `==` or `<` whose two
    /// parameters have one type, a dotted path once generic arguments,
    /// attributes and specifiers are stripped.
    static func operatorWitness(_ function: FunctionDeclSyntax) -> LawFileFacts.OperatorWitness? {
        let witness: LawFileFacts.Witness
        switch function.name.text {
        case "==":
            witness = .equalTo

        case "<":
            witness = .lessThan

        default:
            return nil
        }
        let parameters = function.signature.parameterClause.parameters
        let types = parameters.compactMap { parameter in
            LawCallReader.typeName(baseType(parameter.type).trimmedDescription)
        }
        guard parameters.count == operatorArity, types.count == operatorArity,
              let typeName = types.first, types.last == typeName else {
            return nil
        }
        return LawFileFacts.OperatorWitness(
            typeName: typeName,
            witness: witness,
            fileScoped: FunctionCollector.isFileScoped(function.modifiers)
        )
    }

    /// `type` without attributes and specifiers such as `borrowing`.
    private static func baseType(_ type: TypeSyntax) -> TypeSyntax {
        type.as(AttributedTypeSyntax.self).map { baseType($0.baseType) } ?? type
    }

    /// The witnesses one member declares.
    private static func witnesses(of decl: DeclSyntax) -> Set<LawFileFacts.Witness> {
        if let ifConfig = decl.as(IfConfigDeclSyntax.self) {
            return ifConfig.clauses.reduce(into: []) { result, clause in
                if let nested = clause.elements?.as(MemberBlockItemListSyntax.self) {
                    result.formUnion(witnesses(in: nested))
                }
            }
        }
        if let function = decl.as(FunctionDeclSyntax.self) {
            return witnesses(of: function)
        }
        if let initializer = decl.as(InitializerDeclSyntax.self) {
            let parameters = initializer.signature.parameterClause.parameters
            switch parameters.first?.firstName.text {
            case "from":
                return isCoder(parameters, named: "Decoder") ? [.initFrom] : []

            case "rawValue":
                return [.initRawValue]

            default:
                return []
            }
        }
        if let variable = decl.as(VariableDeclSyntax.self) {
            return witnesses(of: variable)
        }
        return typeName(of: decl) == "CodingKeys" ? [.codingKeys] : []
    }

    /// The witnesses a function declares.
    private static func witnesses(of function: FunctionDeclSyntax) -> Set<LawFileFacts.Witness> {
        let parameters = function.signature.parameterClause.parameters
        let firstLabel = parameters.first?.firstName.text
        switch (function.name.text, firstLabel) {
        case ("==", _):
            return [.equalTo]

        case ("<", _):
            return [.lessThan]

        case ("hash", "into"):
            return [.hashInto]

        case ("encode", "to"):
            return isCoder(parameters, named: "Encoder") ? [.encodeTo] : []

        default:
            return []
        }
    }

    /// The witnesses a property declaration's bindings declare.
    private static func witnesses(of variable: VariableDeclSyntax) -> Set<LawFileFacts.Witness> {
        variable.bindings.reduce(into: []) { result, binding in
            switch binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
            case "hashValue":
                result.insert(.hashValue)

            case "rawValue":
                result.insert(.rawValue)

            case "allCases":
                result.insert(.allCases)

            default:
                break
            }
        }
    }

    /// Whether `parameters` are the single parameter of a Codable witness,
    /// typed `coder` (`Decoder` or `Encoder`), bare, `any`, `some` or
    /// `Swift.`-qualified, so a conversion such as `init(from other: Model)`
    /// isn't one.
    private static func isCoder(_ parameters: FunctionParameterListSyntax, named coder: String) -> Bool {
        guard parameters.count == 1, let type = parameters.first?.type else {
            return false
        }
        let written = type.trimmedDescription.filter { $0.isWhitespace == false }
        return [coder, "Swift." + coder].contains { name in
            [name, "any" + name, "some" + name].contains(written)
        }
    }

    /// The name of a nested type or typealias, if `decl` is one.
    private static func typeName(of decl: DeclSyntax) -> String? {
        if let typeAlias = decl.as(TypeAliasDeclSyntax.self) {
            return typeAlias.name.text
        }
        if let enumDecl = decl.as(EnumDeclSyntax.self) {
            return enumDecl.name.text
        }
        if let structDecl = decl.as(StructDeclSyntax.self) {
            return structDecl.name.text
        }
        return decl.as(ClassDeclSyntax.self)?.name.text
    }
}

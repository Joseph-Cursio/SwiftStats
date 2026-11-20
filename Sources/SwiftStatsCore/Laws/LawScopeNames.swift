//
//  LawScopeNames.swift
//  SwiftStatsCore
//
//  The names a declaration puts in scope for law detection (PRD §7.11):
//  a generic type's parameters, a protocol's associated types, the names an
//  extension's `where` clause constrains, and the types and typealiases a
//  function body, closure or local type declares.
//

import SwiftSyntax

/// Reads the names declarations put in scope.
enum LawScopeNames {
    /// The parameter names of a generic parameter clause.
    static func names(_ clause: GenericParameterClauseSyntax?) -> [String] {
        clause?.parameters.map(\.name.text) ?? []
    }

    /// The types and typealiases `statements` declare directly, `#if`
    /// branches included.
    static func localNames(in statements: CodeBlockItemListSyntax) -> LawCallReader.LocalNames {
        statements.reduce(into: LawCallReader.LocalNames()) { result, statement in
            if let decl = statement.item.as(DeclSyntax.self) {
                result.formUnion(localNames(of: decl))
            }
        }
    }

    /// The types and typealiases `members` declare directly, `#if`
    /// branches included.
    static func localNames(in members: MemberBlockItemListSyntax) -> LawCallReader.LocalNames {
        members.reduce(into: LawCallReader.LocalNames()) { result, member in
            result.formUnion(localNames(of: member.decl))
        }
    }

    /// The name `decl` declares if it is a type or typealias, or the names
    /// its `#if` branches declare.
    static func localNames(of decl: DeclSyntax) -> LawCallReader.LocalNames {
        var names = LawCallReader.LocalNames()
        if let ifConfig = decl.as(IfConfigDeclSyntax.self) {
            for clause in ifConfig.clauses {
                if let statements = clause.elements?.as(CodeBlockItemListSyntax.self) {
                    names.formUnion(localNames(in: statements))
                }
                if let members = clause.elements?.as(MemberBlockItemListSyntax.self) {
                    names.formUnion(localNames(in: members))
                }
            }
        } else if let alias = decl.as(TypeAliasDeclSyntax.self) {
            names.aliases[alias.name.text] = aliasValue(alias)
        } else if let name = decl.as(StructDeclSyntax.self)?.name
            ?? decl.as(ClassDeclSyntax.self)?.name
            ?? decl.as(EnumDeclSyntax.self)?.name
            ?? decl.as(ActorDeclSyntax.self)?.name {
            names.types.insert(name.text)
        }
        return names
    }

    /// The type `alias` names: a dotted path with generic arguments
    /// stripped, else its value as written.
    static func aliasValue(_ alias: TypeAliasDeclSyntax) -> String {
        let written = alias.initializer.value.trimmedDescription
        return LawCallReader.typeName(written) ?? written
    }

    /// The associated types a protocol's body and primary associated type
    /// clause name, `#if` branches included.
    static func associatedTypes(of node: ProtocolDeclSyntax) -> [String] {
        let primary = node.primaryAssociatedTypeClause?.primaryAssociatedTypes.map(\.name.text) ?? []
        return primary + associatedTypes(in: node.memberBlock.members)
    }

    /// The associated types `members` declare, `#if` branches included.
    static func associatedTypes(in members: MemberBlockItemListSyntax) -> [String] {
        members.flatMap { member -> [String] in
            if let associated = member.decl.as(AssociatedTypeDeclSyntax.self) {
                return [associated.name.text]
            }
            let clauses = member.decl.as(IfConfigDeclSyntax.self).map { Array($0.clauses) } ?? []
            return clauses.flatMap { clause in
                clause.elements?.as(MemberBlockItemListSyntax.self).map(associatedTypes(in:)) ?? []
            }
        }
    }

    /// The first component of each constrained type in a `where` clause:
    /// `Element` in `where Element: Hashable` or `where Element.Key == Int`.
    static func constrainedNames(_ clause: GenericWhereClauseSyntax?) -> [String] {
        clause?.requirements.compactMap { requirement -> String? in
            let constrained: TypeSyntax
            switch requirement.requirement {
            case .conformanceRequirement(let conformance):
                constrained = conformance.leftType

            case .sameTypeRequirement(let sameType):
                guard let type = sameType.leftType.as(TypeSyntax.self) else {
                    return nil
                }
                constrained = type

            default:
                return nil
            }
            return constrained.trimmedDescription.split(separator: ".").first.map(String.init)
        } ?? []
    }
}

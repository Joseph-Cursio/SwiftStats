//
//  Conformances.swift
//  SwiftStatsCore
//
//  A declaration's inheritance clause as names (PRD §7.11): attributes
//  such as `@retroactive` and `@unchecked` unwrapped, a `Swift.` or
//  `PropertyLawKit.` qualifier stripped, compositions split at `&`, and
//  suppressions such as `~Copyable` dropped.
//

import SwiftSyntax

/// Reads inheritance clauses.
enum Conformances {
    /// The clause's names, normalised, in written order; empty without a clause.
    static func written(_ clause: InheritanceClauseSyntax?) -> [String] {
        clause?.inheritedTypes.flatMap { names(of: $0.type) } ?? []
    }

    /// The clause's names, normalised, sorted and without repeats.
    static func sorted(_ clause: InheritanceClauseSyntax?) -> [String] {
        Array(Set(written(clause))).sorted()
    }

    /// The names one inherited type contributes.
    private static func names(of type: TypeSyntax) -> [String] {
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return names(of: attributed.baseType)
        }
        if let composition = type.as(CompositionTypeSyntax.self) {
            return composition.elements.flatMap { names(of: $0.type) }
        }
        if type.is(SuppressedTypeSyntax.self) {
            return []
        }
        return [unqualified(CanonicalText.render(type))]
    }

    /// `name` without a qualifier that names the same protocol.
    static func unqualified(_ name: String) -> String {
        for qualifier in KitProtocols.qualifiers where name.hasPrefix(qualifier) && name.count > qualifier.count {
            return String(name.dropFirst(qualifier.count))
        }
        return name
    }
}

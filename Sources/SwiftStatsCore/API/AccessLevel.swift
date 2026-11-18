//
//  AccessLevel.swift
//  SwiftStatsCore
//
//  Swift's access levels, least visible first (PRD §7.5).
//

import SwiftSyntax

/// A declaration's access level.
enum AccessLevel: Int, Comparable, CaseIterable {
    case `fileprivate` = 1
    case `internal` = 2
    case `private` = 0
    case `public` = 4
    case open = 5
    case package = 3

    /// The level's keyword, as roll-ups name it.
    var name: String {
        String(describing: self)
    }

    /// The level a modifier list writes, ignoring setter-only ones such as
    /// `private(set)`; nil when it writes none.
    static func written(in modifiers: DeclModifierListSyntax) -> Self? {
        for modifier in modifiers where modifier.detail == nil {
            switch modifier.name.tokenKind {
            case .keyword(.private):
                return .private

            case .keyword(.fileprivate):
                return .fileprivate

            case .keyword(.internal):
                return .internal

            case .keyword(.package):
                return .package

            case .keyword(.public):
                return .public

            case .keyword(.open):
                return .open

            default:
                continue
            }
        }
        return nil
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

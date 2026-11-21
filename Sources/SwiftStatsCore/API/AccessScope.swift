//
//  AccessScope.swift
//  SwiftStatsCore
//
//  The access rules of one level of nesting (PRD §7.5), shared by the API
//  surface's declarations and the function records' access (M5), so the
//  two can't disagree: a declaration's effective level is what it writes,
//  or its scope's default, capped by the scope. A type's members are
//  capped by the type (a `private` type at file scope by `fileprivate`,
//  since its members are visible in the whole file); an extension's
//  modifier becomes its members' default and cap, `private` reading as
//  `fileprivate`.
//

import SwiftSyntax

/// What a declaration's scope does to its access level.
struct AccessScope {
    /// The file's own scope: members default to `internal` and nothing caps them.
    static let file = Self(defaultLevel: .internal, defaultIsWritten: false, cap: .open)

    /// The level an unmodified member gets (`internal`, or an extension's).
    let defaultLevel: AccessLevel
    /// Whether that default came from an extension's modifier.
    let defaultIsWritten: Bool
    /// The most visible level a member can have here.
    let cap: AccessLevel

    /// The effective level of a declaration here that writes `written`.
    func level(written: AccessLevel?) -> AccessLevel {
        min(written ?? defaultLevel, cap)
    }

    /// The effective level of a declaration here with `modifiers`.
    func level(of modifiers: DeclModifierListSyntax) -> AccessLevel {
        level(written: AccessLevel.written(in: modifiers))
    }

    /// The scope of the members of a type declared here at `access`;
    /// `isAtFileScope` when this is the file's own scope.
    func members(ofTypeAt access: AccessLevel, isAtFileScope: Bool) -> Self {
        // A `private` type's members are visible in its enclosing scope:
        // the whole file when it is at file scope.
        let typeCap = access == .private && isAtFileScope ? AccessLevel.fileprivate : access
        return Self(defaultLevel: .internal, defaultIsWritten: false, cap: typeCap)
    }

    /// The scope of the members of an extension declared here with `modifiers`.
    func members(ofExtensionWith modifiers: DeclModifierListSyntax) -> Self {
        guard let written = AccessLevel.written(in: modifiers) else {
            return Self(defaultLevel: .internal, defaultIsWritten: false, cap: cap)
        }
        // Members of a `private` extension are `fileprivate`.
        let level = max(written, .fileprivate)
        return Self(defaultLevel: level, defaultIsWritten: true, cap: min(cap, level))
    }
}

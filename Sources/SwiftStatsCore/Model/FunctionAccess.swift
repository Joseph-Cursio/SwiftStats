//
//  FunctionAccess.swift
//  SwiftStatsCore
//
//  A function record's effective access level (M5, PRD §7.5), by the
//  rules the API surface counts declarations with, plus `local` for what
//  is declared inside another record or a property's initialiser, which
//  no other code can name.
//

/// A record's effective access level.
public enum FunctionAccess: String, Codable, CaseIterable, Sendable {
    /// `fileprivate`.
    case `fileprivate`
    /// `internal`, written or by default.
    case `internal`
    /// `private`.
    case `private`
    /// `public`.
    case `public`
    /// Declared inside another record or an initialiser's closure.
    case local
    /// `open`.
    case open
    /// `package`.
    case package

    /// Whether code outside the package can call it: `public` or `open`.
    public var isPublic: Bool {
        self == .public || self == .open
    }

    /// The record access of a declaration level.
    init(_ level: AccessLevel) {
        switch level {
        case .private:
            self = .private

        case .fileprivate:
            self = .fileprivate

        case .internal:
            self = .internal

        case .package:
            self = .package

        case .public:
            self = .public

        case .open:
            self = .open
        }
    }
}

//
//  TypeKind.swift
//  SwiftStatsCore
//
//  The kinds of type declaration a scan counts (PRD §7.2).
//

/// What a type declaration declares.
public enum TypeKind: String, Codable, CaseIterable, Sendable {
    /// An `actor`.
    case actor
    /// A `class`.
    case classType = "class"
    /// An `enum`.
    case enumType = "enum"
    /// An `extension`, counted on its own: it adds to a type, it isn't one.
    case extensionDeclaration = "extension"
    /// A `protocol`.
    case protocolType = "protocol"
    /// A `struct`.
    case structType = "struct"
}

//
//  TypeRecord.swift
//  SwiftStatsCore
//
//  One row per type declaration or extension (PRD §7.2), nested and local
//  ones included, for type counts, body length and member count.
//

/// A single type declaration or extension and its size.
public struct TypeRecord: Codable, Hashable, Sendable {
    /// The target (module) the declaration belongs to.
    public let module: String
    /// What it declares.
    public let kind: TypeKind
    /// The lexical path: enclosing types and the name, dot-separated
    /// (`Outer.Inner`); for an extension, the extended type as written.
    public let name: String
    /// Path of the file, relative to the package root.
    public let file: String
    /// The declaration's source range, attributes included.
    public let range: SourceSpan
    /// Lines that hold at least one token of the declaration, attributes
    /// (its members' included) and comments excluded; nested declarations
    /// count toward it.
    public let strippedLines: Int
    /// Declarations directly in its body, `#if` branches flattened: each
    /// function, initialiser, deinitialiser, subscript, typealias,
    /// associated type and nested type counts once, each pattern binding of
    /// a property and each enum case element counts once.
    public let memberCount: Int
    /// Whether it is declared inside a function body or other code.
    public let isLocal: Bool
    /// The `#if` condition the declaration sits under, if any.
    public let ifConfig: String?

    /// Creates a record. Fields are documented on their properties.
    public init(
        module: String,
        kind: TypeKind,
        name: String,
        file: String,
        range: SourceSpan,
        strippedLines: Int,
        memberCount: Int,
        isLocal: Bool,
        ifConfig: String?
    ) {
        self.module = module
        self.kind = kind
        self.name = name
        self.file = file
        self.range = range
        self.strippedLines = strippedLines
        self.memberCount = memberCount
        self.isLocal = isLocal
        self.ifConfig = ifConfig
    }
}

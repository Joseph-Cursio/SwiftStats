//
//  IndexOccurrenceFact.swift
//  SwiftStatsCore
//
//  One occurrence of a symbol in a record, as an `IndexStoreSource` gives
//  it (M7, design §2.2): where it is (1-based line, 1-based column in
//  UTF-8 bytes, as SwiftSyntax counts), its roles, the symbol, and the
//  symbols it relates to. Kinds, subkinds, properties and roles are the
//  raw numbers the store holds; `IndexSymbolKind` names the ones
//  SwiftStats reads. Its coding keys are those of
//  `Scripts/index-check.py dump`.
//

/// One occurrence of a symbol, copied out of the reader.
struct IndexOccurrenceFact: Decodable, Hashable, Sendable {
    /// A symbol the occurrence relates to, and how.
    struct Relation: Decodable, Hashable, Sendable {
        /// The relation's role bits (`IndexSymbolKind.RelationRole`).
        let roles: UInt64
        /// The related symbol's USR.
        let usr: String
        /// The related symbol's name.
        let name: String
        /// The related symbol's kind, raw.
        let kind: Int
        /// The related symbol's subkind, raw.
        let subkind: Int
        /// The related symbol's property bits, raw.
        let properties: UInt64
    }

    /// The 1-based line.
    let line: Int
    /// The 1-based column, in UTF-8 bytes.
    let column: Int
    /// The occurrence's role bits as stored, relation bits included
    /// (`IndexSymbolKind.Role`, `IndexSymbolKind.RelationRole`).
    let roles: UInt64
    /// The symbol's USR.
    let usr: String
    /// The symbol's name.
    let name: String
    /// The symbol's kind, raw (`IndexSymbolKind`).
    let kind: Int
    /// The symbol's subkind, raw (`IndexSymbolKind.Subkind`).
    let subkind: Int
    /// The symbol's property bits, raw (`IndexSymbolKind.Property`).
    let properties: UInt64
    /// The symbols the occurrence relates to.
    let relations: [Relation]
}

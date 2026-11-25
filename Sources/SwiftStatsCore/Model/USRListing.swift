//
//  USRListing.swift
//  SwiftStatsCore
//
//  One row of the `index` collector's USR lists (M7, design §3.5): a
//  record with several distinct primary USRs (`severalUSRs`, one row per
//  USR), a USR assigned to several records (`sharedUSR`, one row per
//  record), a definition the join gave no record (`noRecord`, with its
//  sub-reason), or a record of a key collision the USR tells apart
//  (`collision`, informative). The position is the definition's, in the
//  package.
//

/// A disagreement, a definition with no record, or a collision's record.
public struct USRListing: Codable, Hashable, Sendable {
    /// The keys the scan JSON writes.
    private enum CodingKeys: String, CodingKey {
        case kind
        case subreason
        case usr
        case key
        case symbolKind
        case name
        case file
        case line
        case column
    }

    /// What the row lists.
    public enum Kind: String, CaseIterable, Sendable {
        /// A record whose key carries a collision suffix, its USR differing
        /// from the other records of the collision.
        case collision
        /// A definition no compatible record holds.
        case noRecord
        /// One record, several distinct primary USRs.
        case severalUSRs
        /// One USR, the primary USR of several records.
        case sharedUSR
    }

    /// Why a definition has no record.
    public enum Subreason: String, CaseIterable, Sendable {
        /// A record holds it, but the innermost one isn't compatible.
        case incompatibleKind
        /// No record holds it and it isn't a requirement.
        case outsideRecords
        /// No record holds it and it is a protocol's requirement: a
        /// requirement without a body.
        case requirement
    }

    /// What the row lists.
    public let kind: Kind
    /// Why a definition has no record; nil for the other kinds.
    public let subreason: Subreason?
    /// The USR.
    public let usr: String?
    /// The record's key: the record in a disagreement or collision, or the
    /// innermost incompatible record; nil when no record holds the
    /// definition.
    public let key: String?
    /// The definition's symbol kind, as the index store numbers it.
    public let symbolKind: Int?
    /// The definition's symbol name.
    public let name: String?
    /// The file, relative to the package root.
    public let file: String
    /// The definition's line.
    public let line: Int
    /// The definition's UTF-8 column.
    public let column: Int

    /// Creates a row. Fields are documented on their properties.
    public init(
        kind: Kind,
        subreason: Subreason?,
        usr: String?,
        key: String?,
        symbolKind: Int?,
        name: String?,
        file: String,
        line: Int,
        column: Int
    ) {
        self.kind = kind
        self.subreason = subreason
        self.usr = usr
        self.key = key
        self.symbolKind = symbolKind
        self.name = name
        self.file = file
        self.line = line
        self.column = column
    }

    /// Reads a row; it throws for a kind or sub-reason no SwiftStats
    /// writes.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kindName = try container.decode(String.self, forKey: .kind)
        guard let listed = Kind(rawValue: kindName) else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "no kind \(kindName)"
            )
        }
        var why: Subreason?
        if let written = try container.decodeIfPresent(String.self, forKey: .subreason) {
            why = Subreason(rawValue: written)
            guard why != nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .subreason,
                    in: container,
                    debugDescription: "no sub-reason \(written)"
                )
            }
        }
        try self.init(
            kind: listed,
            subreason: why,
            usr: container.decodeIfPresent(String.self, forKey: .usr),
            key: container.decodeIfPresent(String.self, forKey: .key),
            symbolKind: container.decodeIfPresent(Int.self, forKey: .symbolKind),
            name: container.decodeIfPresent(String.self, forKey: .name),
            file: container.decode(String.self, forKey: .file),
            line: container.decode(Int.self, forKey: .line),
            column: container.decode(Int.self, forKey: .column)
        )
    }

    /// Writes the row, its kind and sub-reason as their raw values, leaving
    /// out what it doesn't have.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind.rawValue, forKey: .kind)
        try container.encodeIfPresent(subreason?.rawValue, forKey: .subreason)
        try container.encodeIfPresent(usr, forKey: .usr)
        try container.encodeIfPresent(key, forKey: .key)
        try container.encodeIfPresent(symbolKind, forKey: .symbolKind)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(file, forKey: .file)
        try container.encode(line, forKey: .line)
        try container.encode(column, forKey: .column)
    }
}

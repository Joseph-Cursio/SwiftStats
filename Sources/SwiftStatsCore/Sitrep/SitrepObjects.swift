//
//  SitrepObjects.swift
//  SwiftStatsCore
//
//  Sitrep's type counts, with Sitrep's field names. Only types Sitrep sees as
//  top-level are counted (see `SitrepFileVisitor`).
//

/// Sitrep's `objects` block.
public struct SitrepObjects: Codable, Hashable, Sendable {
    /// Top-level structs.
    public let structs: Int
    /// Top-level classes.
    public let classes: Int
    /// Top-level enums.
    public let enums: Int
    /// Top-level protocols.
    public let protocols: Int
    /// Extensions.
    public let extensions: Int

    /// Creates the block. Fields are documented on their properties.
    public init(structs: Int, classes: Int, enums: Int, protocols: Int, extensions: Int) {
        self.structs = structs
        self.classes = classes
        self.enums = enums
        self.protocols = protocols
        self.extensions = extensions
    }
}

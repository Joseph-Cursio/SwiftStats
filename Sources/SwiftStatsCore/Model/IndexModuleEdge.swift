//
//  IndexModuleEdge.swift
//  SwiftStatsCore
//
//  A dependency of one of the package's targets on another module, from
//  the T1 build's index (M7, design §4.2): on another package target, with
//  the reference occurrences from the target's files to definitions in the
//  other's, or on a non-system module of another package, whose references
//  aren't read. Both count the target's files that import the module.
//

/// One module edge.
public struct IndexModuleEdge: Codable, Hashable, Sendable {
    /// What the edge points at.
    public enum Kind: String, Codable, Sendable {
        /// A non-system module of another package, by its C99 name.
        case dependency
        /// Another of the package's targets.
        case `package`
    }

    /// The package target the edge starts at.
    public let fromModule: String
    /// The module it points at: a target name, or another package's C99
    /// module name.
    public let toModule: String
    /// What it points at.
    public let kind: Kind
    /// Distinct reference occurrences (file, line, column, USR, roles) from
    /// `fromModule`'s files to definitions in `toModule`'s; nil for a
    /// dependency edge, whose module's records aren't read.
    public let references: Int?
    /// Distinct main files of `fromModule`'s kept and variant units whose
    /// unit dependencies name `toModule`.
    public let files: Int

    /// Creates the edge. Fields are documented on their properties.
    public init(fromModule: String, toModule: String, kind: Kind, references: Int?, files: Int) {
        self.fromModule = fromModule
        self.toModule = toModule
        self.kind = kind
        self.references = references
        self.files = files
    }
}

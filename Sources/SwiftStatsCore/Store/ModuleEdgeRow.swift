//
//  ModuleEdgeRow.swift
//  SwiftStatsCore
//
//  The `moduleEdge` table (store v6, M7, design §4.2, §9.1): one row per
//  module edge of a snapshot holding index results. A dependency edge has
//  null references: they are counted only between package targets.
//

import GRDB

/// A module edge, as one row.
struct ModuleEdgeRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "moduleEdge"

    /// The snapshot.
    var snapshotId: Int64
    /// The importing target.
    var fromModule: String
    /// The imported module.
    var toModule: String
    /// `package` or `dependency`.
    var kind: IndexModuleEdge.Kind
    /// Reference occurrences across it; null for a dependency edge.
    var references: Int?
    /// Importing files.
    var files: Int

    /// The edge this row holds.
    var edge: IndexModuleEdge {
        IndexModuleEdge(fromModule: fromModule, toModule: toModule, kind: kind, references: references, files: files)
    }

    /// The row for `edge` in snapshot `snapshotId`.
    init(_ edge: IndexModuleEdge, snapshotId: Int64) {
        self.snapshotId = snapshotId
        fromModule = edge.fromModule
        toModule = edge.toModule
        kind = edge.kind
        references = edge.references
        files = edge.files
    }
}

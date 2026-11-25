//
//  SnapshotStore+Rows.swift
//  SwiftStatsCore
//
//  The rows store v3 adds (M4): scan-wide facts, property candidates, law
//  checks, clone classes and their copies, and history's commit log with
//  each family's changes, and from v6 (M7) history's coupling pairs; and
//  reading a snapshot back with all its rows, v4's coverage
//  (`CoverageRows`), v5's mutation results (`MutationRows`) and v6's T1
//  results (`IndexRows`, `BuildRows`, `DeadCodeRows`) among them.
//  Signals read these rows, never the report blob.
//

import GRDB

extension SnapshotStore {
    /// Inserts `report`'s M4 rows as rows of snapshot `snapshotId`.
    static func insertM4Rows(of report: ScanReport, snapshotId: Int64, in database: Database) throws {
        try ScanFactsRow(report, snapshotId: snapshotId).insert(database)
        for (ordinal, candidate) in (report.properties?.candidates ?? []).enumerated() {
            try PropertyCandidateRow(candidate, ordinal: ordinal, snapshotId: snapshotId).insert(database)
        }
        for (ordinal, check) in report.laws.checks.enumerated() {
            try LawCheckRow(check, ordinal: ordinal, snapshotId: snapshotId).insert(database)
        }
        for clone in report.clones?.classes ?? [] {
            try CloneClassRow(clone, snapshotId: snapshotId).insert(database)
            for (offset, instance) in clone.instances.enumerated() {
                try CloneInstanceRow(
                    instance,
                    classOrdinal: clone.ordinal,
                    ordinal: offset + 1,
                    snapshotId: snapshotId
                ).insert(database)
            }
        }
        guard let history = report.history else {
            return
        }
        for (ordinal, entry) in history.commitLog.enumerated() {
            try HistoryCommitRow(entry, ordinal: ordinal, snapshotId: snapshotId).insert(database)
        }
        for change in history.families.flatMap({ FamilyChangeRow.rows(for: $0, snapshotId: snapshotId) }) {
            try change.insert(database)
        }
        for (ordinal, pair) in history.coupling.enumerated() {
            try CouplingPairRow(pair, ordinal: ordinal, snapshotId: snapshotId).insert(database)
        }
    }

    /// Snapshot `id` with its rows, read in `database`.
    static func snapshot(id: Int64, in database: Database) throws -> StoredSnapshot {
        let mine = Column("snapshotId") == id
        let index = try IndexRows(id: id, in: database)?.stored
        return StoredSnapshot(
            id: id,
            info: try info(id: id, in: database),
            reportSchemaVersion: try Int.fetchOne(
                database,
                sql: "SELECT reportSchemaVersion FROM snapshot WHERE id = ?",
                arguments: [id]
            ) ?? 0,
            functions: try FunctionRow.filter(mine)
                .order(Column("key"), Column("file"), Column("startLine"))
                .fetchAll(database),
            findings: try FindingRow.filter(mine)
                .order(Column("tool"), Column("rule"), Column("file"), Column("line"), Column("column"))
                .fetchAll(database),
            rollups: try RollupMetricRow.filter(mine)
                .order(Column("scope"), Column("name"), Column("metric"))
                .fetchAll(database),
            history: try HistoryRunRow.filter(mine).fetchOne(database),
            familyHistory: try FamilyHistoryRow.filter(mine)
                .order(Column("file"), Column("line"), Column("family"))
                .fetchAll(database),
            scanFacts: try ScanFactsRow.filter(mine).fetchOne(database),
            candidates: try PropertyCandidateRow.filter(mine)
                .order(Column("ordinal"))
                .fetchAll(database)
                .map(\.candidate),
            lawChecks: try LawCheckRow.filter(mine).order(Column("ordinal")).fetchAll(database).map(\.check),
            cloneClasses: try cloneClasses(id: id, in: database),
            historyCommits: try HistoryCommitRow.filter(mine)
                .order(Column("ordinal"))
                .fetchAll(database)
                .map(\.entry),
            familyChanges: try FamilyChangeRow.filter(mine)
                .order(Column("family"), Column("file"), Column("commitOrdinal"))
                .fetchAll(database),
            couplingPairs: try CouplingPairRow.filter(mine).order(Column("ordinal")).fetchAll(database).map(\.pair),
            coverage: try CoverageRows(id: id, in: database)?.stored,
            mutation: try MutationRows(id: id, in: database)?.stored,
            index: index,
            build: try BuildRows(id: id, in: database)?.stored,
            deadCode: try DeadCodeRows(id: id, in: database)?.stored,
            executableTargets: index == nil ? [] : try executableTargets(id: id, in: database)
        )
    }

    /// Snapshot `id`'s clone classes with their copies, by ordinal.
    private static func cloneClasses(id: Int64, in database: Database) throws -> [CloneClass] {
        let mine = Column("snapshotId") == id
        let instances = Dictionary(
            grouping: try CloneInstanceRow.filter(mine)
                .order(Column("classOrdinal"), Column("ordinal"))
                .fetchAll(database)
        ) { row in row.classOrdinal }
        return try CloneClassRow.filter(mine).order(Column("ordinal")).fetchAll(database).map { row in
            row.clone(instances: (instances[row.ordinal] ?? []).map(\.instance))
        }
    }
}

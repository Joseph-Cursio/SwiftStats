//
//  SnapshotStore+Rows.swift
//  SwiftStatsCore
//
//  The rows store v3 adds (M4): scan-wide facts, property candidates, law
//  checks, clone classes and their copies, and history's commit log with
//  each family's changes; and reading a snapshot back with all its rows.
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
    }

    /// Snapshot `id` with its rows, read in `database`.
    static func snapshot(id: Int64, in database: Database) throws -> StoredSnapshot {
        let mine = Column("snapshotId") == id
        return StoredSnapshot(
            id: id,
            info: try info(id: id, in: database),
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
                .fetchAll(database)
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

//
//  SnapshotStore.swift
//  SwiftStatsCore
//
//  The SQLite snapshot store (PRD §9, D9): one clean and one dirty snapshot
//  per package and commit, each with its collector runs, function rows,
//  finding rows, roll-up numbers, history, M4 rows (`SnapshotStore+Rows`),
//  coverage rows (`CoverageRows`) and the whole scan report.
//

import Foundation
import GRDB

/// Reads and writes snapshots.
public struct SnapshotStore: Sendable {
    /// How long to wait for another process holding the file, in seconds.
    private static let busyTimeout: TimeInterval = 10

    /// The database file.
    public let url: URL
    /// The connection.
    private let queue: DatabaseQueue

    /// Opens the store at `url`, creating it and its directory if needed and
    /// bringing its schema up to date. A store with migrations this build
    /// doesn't know was written by a newer SwiftStats and is refused.
    public init(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var configuration = Configuration()
        configuration.busyMode = .timeout(Self.busyTimeout)
        let connection = try DatabaseQueue(path: url.path, configuration: configuration)
        let migrator = StoreMigrations.migrator
        if try connection.read({ try migrator.hasBeenSuperseded($0) }) {
            throw StoreError.newerStore(url.path)
        }
        try migrator.migrate(connection)
        self.url = url
        queue = connection
    }

    /// The compact JSON a report is stored as.
    private static func encodeReport(_ report: ScanReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(report)
    }

    /// Inserts `snapshot`'s collector runs, functions, findings, roll-up
    /// numbers and coverage, collected at `coverageCollectedAt`, as rows of
    /// snapshot `snapshotId`.
    private static func insertRows(
        of snapshot: ScannedSnapshot,
        metrics: [(Rollup, [RollupMetrics.Metric])],
        coverageCollectedAt: String,
        snapshotId: Int64,
        in database: Database
    ) throws {
        for run in snapshot.info.collectors {
            try CollectorRunRow(run, snapshotId: snapshotId).insert(database)
        }
        let generated = Set(snapshot.report.files.filter(\.generated).map(\.path))
        for record in snapshot.report.records {
            try FunctionRow(record, snapshotId: snapshotId, generated: generated.contains(record.file)).insert(database)
        }
        for location in snapshot.report.findings.flatMap({ FindingRow.rows(for: $0, snapshotId: snapshotId) }) {
            try location.insert(database)
        }
        if let history = snapshot.report.history {
            try HistoryRunRow(history, snapshotId: snapshotId).insert(database)
            for family in history.families {
                try FamilyHistoryRow(family, snapshotId: snapshotId).insert(database)
            }
        }
        try insertM4Rows(of: snapshot.report, snapshotId: snapshotId, in: database)
        if let coverage = snapshot.report.coverage {
            try CoverageRows(coverage, collectedAt: coverageCollectedAt, snapshotId: snapshotId).insert(database)
        }
        for (rollup, numbers) in metrics {
            for number in numbers {
                try RollupMetricRow(
                    snapshotId: snapshotId,
                    scope: rollup.scope,
                    name: rollup.name,
                    metric: number.path,
                    collector: number.collector,
                    value: number.value
                ).insert(database)
            }
        }
    }

    /// The metadata of snapshot `id`, read in `database`.
    static func info(id: Int64, in database: Database) throws -> SnapshotInfo {
        guard let row = try SnapshotRow.fetchOne(database, key: id) else {
            throw StoreError.noSnapshot("id \(id)")
        }
        let runs = try CollectorRunRow
            .filter(Column("snapshotId") == id)
            .order(Column("name"))
            .fetchAll(database)
        return row.info(collectors: runs.map(\.info))
    }

    /// Stores `snapshot`, replacing any snapshot of the same package, commit
    /// and dirtiness (PRD §6.2), and returns its id. Its coverage, if any,
    /// is dated `coverageCollectedAt` when given (coverage carried from an
    /// earlier scan), else the snapshot's own date.
    @discardableResult
    public func save(_ snapshot: ScannedSnapshot, coverageCollectedAt: String? = nil) throws -> Int64 {
        let json = try Self.encodeReport(snapshot.report)
        let compressed = try ReportCompression.deflate(json)
        let metrics = try snapshot.report.rollups.map { rollup in
            (rollup, try RollupMetrics.metrics(of: rollup))
        }
        return try queue.write { database in
            let git = snapshot.info.git
            try database.execute(
                sql: """
                    DELETE FROM snapshot
                    WHERE package = ? AND packagePath = ? AND ifnull(commitHash, '') = ? AND isDirty = ?
                    """,
                arguments: [snapshot.info.package, git.packagePath, git.commit ?? "", git.isDirty]
            )
            var row = SnapshotRow(snapshot.info, reportSchemaVersion: snapshot.report.schemaVersion)
            try row.insert(database)
            guard let id = row.id else {
                throw StoreError.corruptReport("the snapshot row got no id")
            }
            try Self.insertRows(
                of: snapshot,
                metrics: metrics,
                coverageCollectedAt: coverageCollectedAt ?? snapshot.info.date,
                snapshotId: id,
                in: database
            )
            try ReportRow(
                snapshotId: id,
                schemaVersion: snapshot.report.schemaVersion,
                encoding: ReportCompression.encoding,
                uncompressedLength: json.count,
                data: compressed
            ).insert(database)
            return id
        }
    }

    /// The snapshot of `package` at `packagePath` for `commit` (nil outside
    /// git) with the given dirtiness, if stored.
    public func snapshotID(package: String, packagePath: String, commit: String?, isDirty: Bool) throws -> Int64? {
        try queue.read { database in
            try Int64.fetchOne(
                database,
                sql: """
                    SELECT id FROM snapshot
                    WHERE package = ? AND packagePath = ? AND ifnull(commitHash, '') = ? AND isDirty = ?
                    """,
                arguments: [package, packagePath, commit ?? "", isDirty]
            )
        }
    }

    /// The newest snapshot at `packagePath` of `commit` with dirtiness
    /// `isDirty`, whatever the package was called then. A full commit hash
    /// and the package path name one package tree, whose name can change
    /// from commit to commit.
    public func snapshotID(packagePath: String, commit: String, isDirty: Bool) throws -> Int64? {
        try queue.read { database in
            try Int64.fetchOne(
                database,
                sql: """
                    SELECT max(id) FROM snapshot
                    WHERE packagePath = ? AND commitHash = ? AND isDirty = ?
                    """,
                arguments: [packagePath, commit, isDirty]
            )
        }
    }

    /// The most recently taken snapshot of `package` at `packagePath`.
    public func latestSnapshotID(package: String, packagePath: String) throws -> Int64? {
        try queue.read { database in
            try Int64.fetchOne(
                database,
                sql: """
                    SELECT id FROM snapshot WHERE package = ? AND packagePath = ?
                    ORDER BY date DESC, id DESC LIMIT 1
                    """,
                arguments: [package, packagePath]
            )
        }
    }

    /// The clean snapshots of `package` at `packagePath`, with their commits.
    public func cleanSnapshots(package: String, packagePath: String) throws -> [(id: Int64, commit: String)] {
        try queue.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT id, commitHash FROM snapshot
                    WHERE package = ? AND packagePath = ? AND isDirty = 0 AND commitHash IS NOT NULL
                    ORDER BY id
                    """,
                arguments: [package, packagePath]
            )
            return rows.map { row in (id: row["id"], commit: row["commitHash"]) }
        }
    }

    /// The value of roll-up number `metric` in the roll-up `name` of `scope`
    /// in snapshot `id`; nil when that snapshot has no such number.
    public func rollupValue(id: Int64, scope: RollupScope, name: String, metric: String) throws -> Double? {
        try queue.read { database in
            try Double.fetchOne(
                database,
                sql: "SELECT value FROM rollupMetric WHERE snapshotId = ? AND scope = ? AND name = ? AND metric = ?",
                arguments: [id, scope.rawValue, name, metric]
            )
        }
    }

    /// Whether snapshot `id` holds any number in the roll-up `name` of
    /// `scope`: false when that module or part wasn't there.
    func hasRollup(id: Int64, scope: RollupScope, name: String) throws -> Bool {
        try queue.read { database in
            try Bool.fetchOne(
                database,
                sql: "SELECT EXISTS (SELECT 1 FROM rollupMetric WHERE snapshotId = ? AND scope = ? AND name = ?)",
                arguments: [id, scope.rawValue, name]
            ) ?? false
        }
    }

    /// The metadata of snapshot `id`.
    public func info(id: Int64) throws -> SnapshotInfo {
        try queue.read { database in try Self.info(id: id, in: database) }
    }

    /// Snapshot `id` with its rows.
    public func load(id: Int64) throws -> StoredSnapshot {
        try queue.read { database in try Self.snapshot(id: id, in: database) }
    }

    /// The coverage snapshot `id` holds, for a rescan that may carry it
    /// (`SnapshotStore+Coverage`); nil when it holds none.
    func heldCoverage(id: Int64) throws -> HeldCoverage? {
        try queue.read { database in try Self.heldCoverage(id: id, in: database) }
    }

    /// Snapshot `id`'s scan report. One written with another report schema
    /// can't be read by this build, and the error says to rescan.
    public func report(id: Int64) throws -> ScanReport {
        let row = try queue.read { database in
            try ReportRow.filter(Column("snapshotId") == id).fetchOne(database)
        }
        guard let row else {
            throw StoreError.noSnapshot("id \(id)")
        }
        guard row.schemaVersion == ScanReport.currentSchemaVersion else {
            throw StoreError.reportSchema(stored: row.schemaVersion, current: ScanReport.currentSchemaVersion)
        }
        guard row.encoding == ReportCompression.encoding else {
            throw StoreError.corruptReport("unknown encoding \(row.encoding)")
        }
        let json = try ReportCompression.inflate(row.data, length: row.uncompressedLength)
        return try JSONDecoder().decode(ScanReport.self, from: json)
    }
}

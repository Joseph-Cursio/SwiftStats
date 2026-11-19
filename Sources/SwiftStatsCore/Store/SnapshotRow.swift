//
//  SnapshotRow.swift
//  SwiftStatsCore
//
//  The `snapshot` table (PRD §6.2, §9).
//

import GRDB

/// One snapshot's metadata.
struct SnapshotRow: Codable, FetchableRecord, MutablePersistableRecord {
    /// The table name.
    static let databaseTableName = "snapshot"

    /// The row id; nil until inserted.
    var id: Int64?
    /// The package name.
    var package: String
    /// The package directory's path from the repository's top level.
    var packagePath: String
    /// HEAD's commit; nil outside git.
    var commitHash: String?
    /// The branch; nil when detached.
    var branch: String?
    /// ISO 8601, UTC, whole seconds.
    var date: String
    /// Whether the package directory had changes against HEAD.
    var isDirty: Bool
    /// A hash of those changes.
    var dirtyHash: String?
    /// The first line of `swift --version`.
    var swiftVersion: String?
    /// swiftly's selection.
    var swiftlySelection: String?
    /// The SDK version.
    var sdkVersion: String?
    /// The stored report's `schemaVersion`.
    var reportSchemaVersion: Int

    /// The row for `info`, whose report has `schemaVersion`.
    init(_ info: SnapshotInfo, reportSchemaVersion: Int) {
        id = nil
        package = info.package
        packagePath = info.git.packagePath
        commitHash = info.git.commit
        branch = info.git.branch
        date = info.date
        isDirty = info.git.isDirty
        dirtyHash = info.git.dirtyHash
        swiftVersion = info.toolchain.swiftVersion
        swiftlySelection = info.toolchain.swiftlySelection
        sdkVersion = info.toolchain.sdkVersion
        self.reportSchemaVersion = reportSchemaVersion
    }

    /// Keeps the id SQLite assigned.
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// The metadata, with `collectors`.
    func info(collectors: [CollectorRunInfo]) -> SnapshotInfo {
        SnapshotInfo(
            package: package,
            git: GitState(
                commit: commitHash,
                branch: branch,
                isDirty: isDirty,
                dirtyHash: dirtyHash,
                packagePath: packagePath
            ),
            date: date,
            toolchain: Toolchain(
                swiftVersion: swiftVersion,
                swiftlySelection: swiftlySelection,
                sdkVersion: sdkVersion
            ),
            collectors: collectors
        )
    }
}

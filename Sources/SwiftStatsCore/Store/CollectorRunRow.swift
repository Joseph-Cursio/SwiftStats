//
//  CollectorRunRow.swift
//  SwiftStatsCore
//
//  The `collectorRun` table (PRD §6.2, §9).
//

import GRDB

/// One collector's run in a snapshot.
struct CollectorRunRow: Codable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "collectorRun"

    /// The snapshot.
    var snapshotId: Int64
    /// The run, as the snapshot records it.
    var name: String
    /// How it went.
    var state: CollectorState
    /// Why it was skipped or how it failed.
    var reason: String?
    /// The tool's version string.
    var version: String?
    /// The build identity.
    var identity: String?
    /// The commit label.
    var identityLabel: String?
    /// What it was run with, as a JSON array.
    var options: [String]
    /// Wall-clock milliseconds.
    var durationMilliseconds: Int

    /// The run this row records.
    var info: CollectorRunInfo {
        CollectorRunInfo(
            name: name,
            state: state,
            reason: reason,
            version: version,
            identity: identity,
            identityLabel: identityLabel,
            options: options,
            durationMilliseconds: durationMilliseconds
        )
    }

    /// The row for `run` in snapshot `snapshotId`.
    init(_ run: CollectorRunInfo, snapshotId: Int64) {
        self.snapshotId = snapshotId
        name = run.name
        state = run.state
        reason = run.reason
        version = run.version
        identity = run.identity
        identityLabel = run.identityLabel
        options = run.options
        durationMilliseconds = run.durationMilliseconds
    }
}

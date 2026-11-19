//
//  HistoryRunRow.swift
//  SwiftStatsCore
//
//  The `historyRun` table (PRD §9, M3): one row per snapshot whose history
//  was read, with the window its family rows are counted over.
//

import GRDB

/// The history run of one snapshot.
public struct HistoryRunRow: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    /// The table name.
    public static let databaseTableName = "historyRun"

    /// The snapshot.
    var snapshotId: Int64
    /// The commit the history leads up to.
    public var commitHash: String
    /// Its committer date, which anchors the window.
    public var date: String
    /// The window, in days.
    public var windowDays: Int
    /// The first instant in the window.
    public var windowStart: String
    /// How the repository merges.
    public var mergeStyle: MergeStyle
    /// Non-merge commits that changed the package.
    public var commits: Int
    /// Of those, the ones in the window.
    public var windowCommits: Int

    /// The row for `history` in snapshot `snapshotId`.
    init(_ history: HistoryReport, snapshotId: Int64) {
        self.snapshotId = snapshotId
        commitHash = history.commit
        date = history.date
        windowDays = history.windowDays
        windowStart = history.windowStart
        mergeStyle = history.mergeStyle
        commits = history.commits
        windowCommits = history.windowCommits
    }
}

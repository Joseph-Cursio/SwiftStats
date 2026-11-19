//
//  HistoryReport.swift
//  SwiftStatsCore
//
//  What the history collector found (PRD §7.13), as the scan JSON carries
//  it (`schemaVersion: 5`): the window, the repository's merge style, the
//  commits that counted as fixes, reverts and sweeps, each function
//  family's history, and the change-coupling pairs.
//

/// The history collector's findings.
public struct HistoryReport: Codable, Hashable, Sendable {
    /// The commit the history leads up to.
    public let commit: String
    /// Its committer date, which anchors the window.
    public let date: String
    /// The window, in days.
    public let windowDays: Int
    /// The first instant in the window.
    public let windowStart: String
    /// How the repository merges.
    public let mergeStyle: MergeStyle
    /// Non-merge commits that changed the package's Swift files, in all its
    /// history.
    public let commits: Int
    /// Of those, the ones in the window.
    public let windowCommits: Int
    /// Fix commits in the window, counted or not.
    public let fixCommits: [HistoryCommitNote]
    /// Revert commits in the window, counted or not.
    public let revertCommits: [HistoryCommitNote]
    /// Sweeps and ignored commits in the window.
    public let sweepCommits: [HistoryCommitNote]
    /// Every family at the analysed commit, by file, line and id.
    public let families: [FamilyHistory]
    /// Coupled pairs, by support (most first), then ids.
    public let coupling: [CouplingPair]
    /// Problems worth reporting.
    public let warnings: [String]
}

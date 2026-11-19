//
//  HistoryInput.swift
//  SwiftStatsCore
//
//  What the history collector reads: the repository, the commit and the scan's
//  targets, functions and files.
//

import Foundation

/// What the history collector reads.
struct HistoryInput {
    /// The repository's top level.
    let top: URL
    /// The commit whose history is read.
    let commit: String
    /// The package's directory from the top level; empty at the top.
    let packagePath: String
    /// The scan's targets.
    let targets: [TargetSummary]
    /// The scan's function records.
    let records: [FunctionRecord]
    /// The scan's file records.
    let files: [FileRecord]
    /// Files the configuration excludes.
    let excluded: [String]
    /// How to read the history.
    let options: HistoryOptions
}

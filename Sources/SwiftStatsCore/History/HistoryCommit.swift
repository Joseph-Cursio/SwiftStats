//
//  HistoryCommit.swift
//  SwiftStatsCore
//
//  One commit and the package files it changed, as read from `git log`.
//

/// One commit and what it changed in the package.
struct HistoryCommit: Hashable, Sendable {
    /// The commit hash.
    let hash: String
    /// Its committer time, in seconds since 1970.
    let time: Int
    /// The first line of its message.
    let subject: String
    /// The rest of its message.
    let body: String
    /// The files it changed in the package.
    let changes: [FileChange]
}

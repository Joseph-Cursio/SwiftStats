//
//  HistoryCommitNote.swift
//  SwiftStatsCore
//
//  A commit the history report names: a fix, a revert or a sweep in the window.
//

/// A commit the report names: a fix, a revert or a sweep in the window.
public struct HistoryCommitNote: Codable, Hashable, Sendable {
    /// The commit hash.
    public let commit: String
    /// Its committer date.
    public let date: String
    /// Its subject.
    public let subject: String
    /// The package's Swift files it changed.
    public let files: Int
    /// The function families it changed.
    public let families: Int
    /// Why it doesn't count, when it doesn't: `sweep`, `ignored` or `excluded-subject`.
    public let excluded: String?
}

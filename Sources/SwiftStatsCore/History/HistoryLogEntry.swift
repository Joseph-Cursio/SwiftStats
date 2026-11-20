//
//  HistoryLogEntry.swift
//  SwiftStatsCore
//
//  One commit of a history's commit log (PRD §7.13, M4): a commit that
//  changed the package's Swift files, with what history made of it, so a
//  family's changes can be named commit by commit.
//

/// A commit that changed the package's Swift files, as history classified it.
public struct HistoryLogEntry: Codable, Hashable, Sendable {
    /// The commit hash.
    public let hash: String
    /// Its committer date.
    public let date: String
    /// Whether it counts as a sweep: it changed more files than
    /// `history.bulk-files`, or an ignore list names it.
    public let sweep: Bool
    /// Whether it counts as a fix: a fix subject, not excluded, not a sweep.
    public let fix: Bool

    /// Creates an entry. Fields are documented on their properties.
    public init(hash: String, date: String, sweep: Bool, fix: Bool) {
        self.hash = hash
        self.date = date
        self.sweep = sweep
        self.fix = fix
    }
}

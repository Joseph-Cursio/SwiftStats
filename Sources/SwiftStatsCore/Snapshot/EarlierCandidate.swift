//
//  EarlierCandidate.swift
//  SwiftStatsCore
//
//  A stored snapshot that could be the earlier snapshot divergent clones
//  compares with: a clean snapshot with clone data, on the compared
//  commit's first-parent line.
//

/// A clean snapshot with clone data, and its commit.
struct EarlierCandidate {
    /// The snapshot's row id.
    let id: Int64
    /// Its commit.
    let commit: String
    /// The commit's committer time, in seconds since 1970.
    let time: Int
}

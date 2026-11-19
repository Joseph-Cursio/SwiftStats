//
//  CommitSide.swift
//  SwiftStatsCore
//
//  One version of a commit's changed files: their function rows and the line
//  hashes of their bodies.
//

/// One version of a commit's changed files: their rows, and their bodies'
/// line hashes by `file + "\0" + key`.
struct CommitSide {
    /// The rows of every changed file on this side.
    var rows: [FunctionRow] = []
    /// Line hashes by `file + "\0" + key`.
    var lines: [String: [UInt64]] = [:]
}

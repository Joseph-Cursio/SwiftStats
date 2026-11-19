//
//  MergeStyle.swift
//  SwiftStatsCore
//
//  How a repository merges, judged from its first-parent commits (PRD §7.13).
//

/// How a repository merges, judged from its first-parent commits.
public enum MergeStyle: String, Codable, Hashable, Sendable {
    /// No merges and no sign of squashing.
    case linear
    /// Merge commits keep each branch's commits.
    case merge
    /// No merges, and most subjects end in a pull-request number: each
    /// branch arrives as one commit, so history is coarse.
    case squash
}

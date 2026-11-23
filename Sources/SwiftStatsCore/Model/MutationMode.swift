//
//  MutationMode.swift
//  SwiftStatsCore
//
//  How a snapshot's mutation results were made (M6, design §3, §6.1): by
//  one full run, or by a `--since` run merged with a base snapshot's
//  results. A resumed run keeps the mode of the run it continues.
//

/// How mutation results were made.
public enum MutationMode: String, Codable, CaseIterable, Sendable {
    /// One run over every file.
    case full
    /// A run over the files changed since a base snapshot's commit, merged
    /// with that snapshot's results.
    case since
}

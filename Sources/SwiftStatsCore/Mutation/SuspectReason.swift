//
//  SuspectReason.swift
//  SwiftStatsCore
//
//  Why SwiftMutator judged a test suspect (M6, design §2), in the order
//  its rule checks: a failed control run, flakiness when rerun alone, or
//  reach (failing for mutants in too many of the files with kills). The
//  scan JSON and the store write it by name, as a suspect test's `why`.
//

/// Why a test is suspect.
public enum SuspectReason: String, Sendable {
    /// It failed in a control run, with no mutant on.
    case controlRun
    /// Rerun alone, it didn't fail again often enough.
    case flaky
    /// It fails for mutants in too many of the files with kills.
    case reach
}

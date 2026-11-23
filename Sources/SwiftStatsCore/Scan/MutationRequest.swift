//
//  MutationRequest.swift
//  SwiftStatsCore
//
//  How `scan --mutation` asked for the SwiftMutator collector (M6, design
//  §1): a full run, a run of the files changed since a stored snapshot's
//  commit merged with that snapshot's results (`--since`), or the
//  continuation of an interrupted or failed run (`--resume`).
//

/// Which SwiftMutator run a scan asked for.
public enum MutationRequest: Hashable, Sendable {
    /// `scan --mutation`: every mutant of the package.
    case full
    /// `scan --mutation --resume`: the run an earlier scan left
    /// unfinished, in that run's mode.
    case resume
    /// `scan --mutation --since <rev>`: the files changed since the commit
    /// `rev` names, whose clean snapshot holds the results kept for the
    /// rest; `rev` as given on the command line.
    case since(String)
}

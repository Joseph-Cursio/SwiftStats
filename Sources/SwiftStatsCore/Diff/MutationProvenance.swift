//
//  MutationProvenance.swift
//  SwiftStatsCore
//
//  Where one side of a diff got its mutation results (M6, design §8): a
//  full run, or a `--since` run merged with a base snapshot, how many of
//  its mutants were carried from earlier snapshots, and the runs its
//  mutants refer to. A merged snapshot compares like any other when the
//  collector's build and options match, since its figures use the same
//  formula; its provenance is shown as a fact and never makes a diff
//  non-empty.
//

/// Where a snapshot's mutation results came from.
public struct MutationProvenance: Codable, Hashable, Sendable {
    /// One run a snapshot's mutants refer to.
    public struct Run: Codable, Hashable, Sendable {
        /// Its ordinal among the snapshot's runs.
        public let ordinal: Int
        /// A full run or a `--since` run.
        public let mode: MutationMode
        /// The commit it tested; nil outside git.
        public let commit: String?
        /// The commit of the snapshot its rows were carried from; nil for
        /// the snapshot's own run.
        public let carriedFrom: String?
    }

    /// A full run, or a `--since` run merged with a base.
    public let mode: MutationMode
    /// The base snapshot of a merge; nil for a full run.
    public let base: MutationSource?
    /// The mutants, dropped and unmapped ones included.
    public let mutants: Int
    /// How many of them were carried from earlier snapshots.
    public let carried: Int
    /// The runs the mutants refer to, by ordinal.
    public let runs: [Run]

    /// Whether the results are a merge rather than a full run. Only a
    /// merge carries mutants from earlier snapshots: a same-tree carry
    /// keeps a full run's results, and their flags, as they were.
    var isMerged: Bool {
        mode == .since
    }

    /// The provenance of `mutation`; nil when there are no results.
    init?(_ mutation: StoredMutation?) {
        guard let report = mutation?.report else {
            return nil
        }
        mode = report.mode
        base = report.base
        mutants = report.mutants.count
        carried = report.mutants.count(where: \.carried)
        runs = report.runs.map { run in
            Run(ordinal: run.ordinal, mode: run.mode, commit: run.commit, carriedFrom: run.carriedFrom?.commit)
        }
    }
}

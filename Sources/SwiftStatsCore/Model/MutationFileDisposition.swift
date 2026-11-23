//
//  MutationFileDisposition.swift
//  SwiftStatsCore
//
//  What a snapshot's mutation results say of one Swift path of its tree
//  (M6, design §5, §6.1): a full run tests every production path; a
//  `--since` merge retests changed ones, carries unchanged ones, and names
//  those it couldn't resolve, those SwiftMutator's selection held but that
//  no mutant was tested in, and those deleted since the base.
//

/// Where a path's mutation results come from.
public enum MutationFileDisposition: String, Codable, CaseIterable, Sendable {
    /// Unchanged since the base snapshot, whose results it keeps.
    case carried
    /// In the base snapshot's tree, gone from this one.
    case deleted
    /// Tested by this snapshot's run.
    case tested
    /// Changed since the base, but SwiftMutator tested no mutant in it, so
    /// its code no test ran isn't listed.
    case unlisted
    /// Changed since the base but neither retested nor carried, so it has
    /// no results.
    case unresolved
    /// Listed by SwiftMutator, which doesn't mutate it: a test file,
    /// another package's or a build product.
    case untested
}

//
//  MutationSession+Since.swift
//  SwiftStatsCore
//
//  What a `--since` mutation step adds (M6, design §6.1): before
//  SwiftMutator runs, SwiftMutator's own selection is worked out in the
//  copy (`MutationChanges`), which the merge needs for the files a run that
//  writes no results file leaves unlisted and for the test files changed;
//  and when the run ran without a results file, the copy's tree is hashed
//  before the copy ends, since there is no header to take it from.
//

import Foundation

extension MutationSession.Outcome {
    /// The outcome with `changed`, what a `--since` run's copy changed.
    func with(changes changed: MutationChanges?) -> Self {
        Self(
            exit: exit,
            results: results,
            suspects: suspects,
            resultsFile: resultsFile,
            fixedFiles: fixedFiles,
            warmBuildMilliseconds: warmBuildMilliseconds,
            mutatorMilliseconds: mutatorMilliseconds,
            warnings: warnings,
            changes: changed
        )
    }
}

extension MutationSession {
    /// What the copy at `project` changed since the base a `--since` run
    /// merges with, as SwiftMutator's selection lists it; nil for a full
    /// run, which merges with nothing.
    func changes(in project: URL) throws(MutationFailure) -> MutationChanges? {
        guard let base = job.base else {
            return nil
        }
        return try MutationChanges.read(in: project, since: base.commit)
    }

    /// `changes`, what a `--since` run's copy at `project` changed, with the
    /// copy's tree when the run ended as `outcome` without a results file,
    /// which leaves no header to take it from; nil for a full run.
    func withTree(
        _ changes: MutationChanges?,
        after outcome: Outcome,
        in project: URL
    ) throws(MutationFailure) -> MutationChanges? {
        guard let changes, outcome.exit.state == .ran, outcome.results == nil else {
            return changes
        }
        return changes.with(tree: try MutationChanges.tree(of: project))
    }
}

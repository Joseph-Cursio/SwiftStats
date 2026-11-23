//
//  MutationScope.swift
//  SwiftStatsCore
//
//  What a scan's requested SwiftMutator run needs from the scan beyond the
//  package and its configuration (M6, design §1.2, §6.1): the request, the
//  base snapshot a `--since` run (or the resume of one) merges with, the
//  git state the scan read before any collector wrote into the package,
//  whose commit the copy checks out, the files in the package the copy
//  leaves out, such as a store kept there, and whether the scan stores its
//  snapshot, so a run that ran keeps `pending.json` until it is stored.
//

/// A requested SwiftMutator run's part of a scan.
struct MutationScope: Sendable {
    /// Which run the scan asked for.
    let request: MutationRequest
    /// The stored snapshot a `--since` run, or the resume of one, merges
    /// with, chosen before the scan; nil for a full run, and for a run the
    /// scan couldn't choose one for (no store).
    let base: MutationBase?
    /// The package's git state as the scan read it; nil when the scan read
    /// none (`scan --no-store`), so the run reads it.
    let git: GitState?
    /// Files in the package, relative to its root, the copy leaves out.
    let ignoring: [String]
    /// Whether a run that ran keeps `pending.json`, naming its kept
    /// results, until the scan's snapshot is stored.
    var keepsUntilStored = false

    /// The same run, its copy checking out `state`'s commit and leaving out
    /// the files at `ignored`, keeping `pending.json` after a run that ran
    /// when `keeping`.
    func with(git state: GitState?, ignoring ignored: [String], keepsUntilStored keeping: Bool) -> Self {
        Self(request: request, base: base, git: state, ignoring: ignored, keepsUntilStored: keeping)
    }
}

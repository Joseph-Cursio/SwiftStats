//
//  MutationAdapter.swift
//  SwiftStatsCore
//
//  The SwiftMutator collector (M6, design §1). It runs only when asked for
//  with `scan --mutation`, never in `backfill`, in `diff`'s scans of other
//  revisions or with `--rerun`, since a full run takes most of an hour on a
//  real package. Every scan lists its status, so a snapshot says how to run
//  it when it didn't. Running SwiftMutator comes in later steps; until then
//  a requested run whose `swift-mutator` resolves is skipped, saying so.
//

/// The SwiftMutator collector's name, executable and statuses.
enum MutationAdapter {
    /// The collector's name in a snapshot and in `.swiftstats.yml`.
    static let name = "swiftmutator"
    /// SwiftMutator's executable on PATH.
    static let executableName = "swift-mutator"
    /// Why a scan that didn't ask for mutation testing skipped it.
    static let notRequestedReason = "not requested; scan --mutation runs it"
    /// Why a requested run whose `swift-mutator` resolves is skipped while
    /// running it isn't built (M6 steps 3b and later replace it).
    static let notBuiltReason = "the mutation run is not built yet"
    /// Why `scan --mutation --since` is refused while the merge isn't
    /// built (M6 step 6 replaces it).
    static let sinceNotBuiltReason = "--since is not built yet; run scan --mutation for a full run"
    /// Why `scan --mutation --resume` is refused while resuming isn't
    /// built (M6 step 3d replaces it).
    static let resumeNotBuiltReason = "--resume is not built yet; run scan --mutation for a full run"
}

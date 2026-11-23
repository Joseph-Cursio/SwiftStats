//
//  MutationScope.swift
//  SwiftStatsCore
//
//  What a scan's requested SwiftMutator run needs from the scan beyond the
//  package and its configuration (M6, design §1.2): the request, the git
//  state the scan read before any collector wrote into the package, whose
//  commit the copy checks out, and the files in the package the copy
//  leaves out, such as a store kept there.
//

/// A requested SwiftMutator run's part of a scan.
struct MutationScope: Sendable {
    /// Which run the scan asked for.
    let request: MutationRequest
    /// The package's git state as the scan read it; nil when the scan read
    /// none (`scan --no-store`), so the run reads it.
    let git: GitState?
    /// Files in the package, relative to its root, the copy leaves out.
    let ignoring: [String]
}

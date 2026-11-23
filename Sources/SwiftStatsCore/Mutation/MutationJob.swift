//
//  MutationJob.swift
//  SwiftStatsCore
//
//  Everything one SwiftMutator run of a package is given (M6, design §1):
//  the run asked for (a full run, a `--since` run, or the resume of a
//  pending one), the base a `--since` run merges with, the tools, the
//  package and its git state, the scan's hash of each file it parsed,
//  which the copy is checked against, the files the copy leaves out, and
//  `collectors.swiftmutator`'s settings.
//

import Foundation

/// One SwiftMutator run's inputs.
struct MutationJob {
    /// Which run: a full run, a `--since` run, or the resume of the
    /// pending one.
    let request: MutationRequest
    /// The stored snapshot a `--since` run, or the resume of one, merges
    /// with; nil for a full run.
    let base: MutationBase?
    /// The `swift-mutator` to run.
    let mutator: URL
    /// The `swift` of the test command and the warm build, by the
    /// absolute path it was found at.
    let swift: URL
    /// The package root.
    let root: URL
    /// The package's git state, as the scan read it.
    let git: GitState
    /// The SHA-256 of each file the scan parsed, by its path from the
    /// package root.
    let scanned: [String: String]
    /// Files in the package, relative to its root, never copied.
    let ignoring: [String]
    /// `collectors.swiftmutator`; nil when `.swiftstats.yml` has none.
    let settings: CollectorSettings?

    /// The effective settings a pending run records and a resume compares.
    var pendingSettings: PendingMutationRun.Settings {
        PendingMutationRun.Settings(mutator: mutator, swift: swift, settings: settings)
    }
}

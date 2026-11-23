//
//  MutationSince.swift
//  SwiftStatsCore
//
//  What a `--since` run chose (M6, design §2 item 11, §6.1): the header's
//  `since`, the revision, its commit and the merge base the working tree
//  was compared with, and the Swift files that changed, before the
//  excludes and the coverage filter, so test files are among them.
//

/// A `--since` run's choice.
struct MutationSince: Equatable, Sendable {
    /// A file the run chose.
    struct File: Equatable, Sendable {
        /// Its path relative to the project as the disk spells it, as
        /// SwiftMutator records it, not normalised: comparing it with
        /// other paths in NFC is the caller's job.
        let path: String
        /// Its SHA-256 when compared.
        let sha256: String
    }

    /// The revision as given.
    let ref: String
    /// The commit it names.
    let commit: String
    /// The merge base of that commit and HEAD.
    let mergeBase: String
    /// The Swift files that changed, sorted.
    let files: [File]
    /// The project's folders that are repositories of their own, whose
    /// changes weren't compared.
    let foldersNotCompared: [String]
}

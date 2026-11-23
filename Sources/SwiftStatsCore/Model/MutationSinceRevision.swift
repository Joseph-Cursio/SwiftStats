//
//  MutationSinceRevision.swift
//  SwiftStatsCore
//
//  What a `--since` run compared the working tree with (M6, design §3):
//  the revision as given, the commit it names and their merge base with
//  HEAD, from its results header.
//

/// The revision a `--since` run compared with.
public struct MutationSinceRevision: Codable, Hashable, Sendable {
    /// The revision as given.
    public let ref: String
    /// The commit it names.
    public let commit: String
    /// The merge base of that commit and HEAD.
    public let mergeBase: String

    /// Creates the revision. Fields are documented on their properties.
    public init(ref: String, commit: String, mergeBase: String) {
        self.ref = ref
        self.commit = commit
        self.mergeBase = mergeBase
    }
}

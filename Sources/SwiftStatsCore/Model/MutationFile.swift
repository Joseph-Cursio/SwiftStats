//
//  MutationFile.swift
//  SwiftStatsCore
//
//  One Swift path of the tree a snapshot's mutation results describe (M6,
//  design §3, §5): the last run's `project.files`, with SwiftMutator's
//  hash (a symbolic link's is `link:` and the hash of the path it points
//  to), where its results come from, whether it is a test file changed
//  since the base, and the run that tested it. A path deleted since the
//  base has no hash. This tree is what a later merge compares against.
//

/// A path of the tree the mutation results describe.
public struct MutationFile: Codable, Hashable, Sendable {
    /// The path, relative to the package, as SwiftMutator records it.
    public let path: String
    /// Its SHA-256 as SwiftMutator records it; nil for a deleted path.
    public let sha256: String?
    /// Where its results come from.
    public let disposition: MutationFileDisposition
    /// Whether it is a test file changed since the base, against which
    /// carried verdicts weren't retested.
    public let changedTest: Bool
    /// The ordinal of the run that tested it; nil when none did.
    public let run: Int?

    /// Creates a path's entry. Fields are documented on their properties.
    public init(path: String, sha256: String?, disposition: MutationFileDisposition, changedTest: Bool, run: Int?) {
        self.path = path
        self.sha256 = sha256
        self.disposition = disposition
        self.changedTest = changedTest
        self.run = run
    }
}

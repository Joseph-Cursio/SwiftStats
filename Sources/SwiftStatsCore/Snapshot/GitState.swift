//
//  GitState.swift
//  SwiftStatsCore
//
//  Where a package's working tree stands in git (PRD §6.2).
//

/// A package's commit, branch and dirtiness.
public struct GitState: Codable, Hashable, Sendable {
    /// The state of a package outside git.
    public static let outsideGit = Self(commit: nil, branch: nil, isDirty: false, dirtyHash: nil, packagePath: "")

    /// HEAD's commit; nil outside git or before the first commit.
    public let commit: String?
    /// The checked-out branch; nil when HEAD is detached.
    public let branch: String?
    /// Whether the package directory has changes against HEAD, `.swiftstats/` aside.
    public let isDirty: Bool
    /// A hash of those changes; nil when clean.
    public let dirtyHash: String?
    /// The package directory's path from the repository's top level; empty
    /// at the top level or outside git.
    public let packagePath: String

    /// Creates a git state. Fields are documented on their properties.
    public init(commit: String?, branch: String?, isDirty: Bool, dirtyHash: String?, packagePath: String) {
        self.commit = commit
        self.branch = branch
        self.isDirty = isDirty
        self.dirtyHash = dirtyHash
        self.packagePath = packagePath
    }
}

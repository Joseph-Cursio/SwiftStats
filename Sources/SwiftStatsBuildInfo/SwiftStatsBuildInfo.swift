//
//  SwiftStatsBuildInfo.swift
//  SwiftStatsBuildInfo
//
//  SwiftStats' build identity as BuildInfoPlugin embedded it (PRD §6.2).
//

/// What BuildInfoPlugin recorded about this build's source.
public enum SwiftStatsBuildInfo {
    /// The hash of the build inputs at HEAD plus their uncommitted changes;
    /// empty when the build had no git, or git's top level wasn't this package.
    public static let inputHash = generatedInputHash
    /// The commit the build was made from; empty without git.
    public static let commit = generatedCommit
    /// Whether the build inputs had uncommitted changes.
    public static let isDirty = generatedDirty
}

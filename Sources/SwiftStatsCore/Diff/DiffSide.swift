//
//  DiffSide.swift
//  SwiftStatsCore
//
//  Which snapshot one side of a diff is.
//

/// One side of a diff.
public struct DiffSide: Codable, Hashable, Sendable {
    /// The package.
    public let package: String
    /// The commit; nil outside git.
    public let commit: String?
    /// Whether it had uncommitted changes.
    public let isDirty: Bool
    /// When it was taken.
    public let date: String

    /// The side for `info`.
    init(_ info: SnapshotInfo) {
        package = info.package
        commit = info.git.commit
        isDirty = info.git.isDirty
        date = info.date
    }
}

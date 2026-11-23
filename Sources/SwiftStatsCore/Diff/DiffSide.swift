//
//  DiffSide.swift
//  SwiftStatsCore
//
//  Which snapshot one side of a diff is, and where its mutation results
//  came from (M6).
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
    /// Where its mutation results came from; nil when it holds none.
    public let mutation: MutationProvenance?

    /// The side for `info`, holding `mutation`.
    init(_ info: SnapshotInfo, mutation: StoredMutation?) {
        package = info.package
        commit = info.git.commit
        isDirty = info.git.isDirty
        date = info.date
        self.mutation = MutationProvenance(mutation)
    }
}

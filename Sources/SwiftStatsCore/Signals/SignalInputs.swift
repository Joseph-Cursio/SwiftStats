//
//  SignalInputs.swift
//  SwiftStatsCore
//
//  Everything the signals read, gathered by the workspace so the engine
//  stays pure: the snapshot, and for signals that compare it with an
//  earlier snapshot, that snapshot and what git says changed between the
//  two. The git facts are read only when there is an earlier snapshot and
//  git didn't fail.
//

/// The inputs of a report's signals.
public struct SignalInputs: Hashable, Sendable {
    /// The snapshot reported on.
    public let snapshot: StoredSnapshot
    /// The earlier snapshot it is compared with; nil when none qualifies.
    public let earlier: StoredSnapshot?
    /// What a report says about the earlier snapshot: why there is none,
    /// or how it was chosen; nil when there is nothing to say.
    public let earlierNote: String?
    /// The commits after the earlier snapshot's, up to the snapshot's.
    public let since: Set<String>
    /// The old-side ranges of the diff from the earlier snapshot's commit
    /// to the snapshot's, by the earlier commit's path.
    public let hunks: [String: [DiffHunk]]
    /// Why git couldn't give `since` or `hunks`; nil when it could.
    public let gitFailure: String?

    /// The inputs for `snapshot`, compared with `earlier` when given.
    /// Fields are documented on their properties.
    public init(
        snapshot: StoredSnapshot,
        earlier: StoredSnapshot? = nil,
        earlierNote: String? = nil,
        since: Set<String> = [],
        hunks: [String: [DiffHunk]] = [:],
        gitFailure: String? = nil
    ) {
        self.snapshot = snapshot
        self.earlier = earlier
        self.earlierNote = earlierNote
        self.since = since
        self.hunks = hunks
        self.gitFailure = gitFailure
    }
}

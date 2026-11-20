//
//  FamilyHistory.swift
//  SwiftStatsCore
//
//  One function family's history up to the analysed commit.
//

/// One function family's history, up to the analysed commit.
public struct FamilyHistory: Codable, Hashable, Sendable {
    /// The family's id: its root's key, or a computed property's key.
    public let family: String
    /// The family's file.
    public let file: String
    /// Where the family starts.
    public let line: Int
    /// Whether its file is generated.
    public let generated: Bool
    /// Commits in the window that changed it, sweeps aside; null when
    /// the family has no history.
    public let changes: Int?
    /// Sweeps in the window that changed it.
    public let sweepChanges: Int?
    /// Commits that ever changed it, sweeps included.
    public let allChanges: Int?
    /// Fix commits in the window that changed it.
    public let fixes: Int?
    /// Fix commits that ever changed it.
    public let allFixes: Int?
    /// Fix commits weighted by age: each counts 0.5^(age / half-life).
    public let fixScore: Double?
    /// Fixes per change in the window; null when it had no changes.
    public let fixRate: Double?
    /// Revert commits in the window that touched it.
    public let reverts: Int?
    /// Fixes in the window that came within the repeat window of an earlier fix to it.
    public let repeatedFixes: Int?
    /// Of its changes in the window, those that also changed a matching test file.
    public let testChanges: Int?
    /// Whether a test file matching it by name exists.
    public let hasTests: Bool
    /// When it first appeared.
    public let firstSeen: String?
    /// When it last changed.
    public let lastChanged: String?
    /// How surely its history was traced.
    public let tracedBy: TracedBy
    /// The commits that changed it, sweeps included, as positions in the
    /// history's `commitLog`; null when the family has no history.
    public let changedBy: CommitOrdinals?
}

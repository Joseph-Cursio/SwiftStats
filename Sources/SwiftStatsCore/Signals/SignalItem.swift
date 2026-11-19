//
//  SignalItem.swift
//  SwiftStatsCore
//
//  One function family in a signal's ranking, with the inputs its score
//  came from, so a reader can see why it is there.
//

/// A family's place in a signal.
public struct SignalItem: Codable, Hashable, Sendable {
    /// Its position, from 1.
    public let rank: Int
    /// The family's id.
    public let family: String
    /// Its file.
    public let file: String
    /// Where it starts.
    public let line: Int
    /// Its score; higher ranks first.
    public let score: Double
    /// Whether it is a member of the signal, not only ranked.
    public let member: Bool
    /// Commits in the window that changed it, sweeps aside.
    public let changes: Int
    /// Its cognitive complexity (a property's: its most complex accessor's).
    public let cognitive: Int?
    /// Fix commits in the window.
    public let fixes: Int
    /// Fix commits ever.
    public let allFixes: Int
    /// Fixes weighted by age.
    public let fixScore: Double
    /// Reverts in the window.
    public let reverts: Int
    /// Repeated fixes in the window.
    public let repeatedFixes: Int
    /// Changes in the window that changed a matching test too.
    public let testChanges: Int
    /// When it first appeared.
    public let firstSeen: String?
    /// How surely its history was traced.
    public let tracedBy: TracedBy
}

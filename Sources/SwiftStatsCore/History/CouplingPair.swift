//
//  CouplingPair.swift
//  SwiftStatsCore
//
//  Two function families that change together.
//

/// Two families that change together.
public struct CouplingPair: Codable, Hashable, Sendable {
    /// The first family, in key order.
    public let familyA: String
    /// Its file.
    public let fileA: String
    /// The second family.
    public let familyB: String
    /// Its file.
    public let fileB: String
    /// Commits in the window that changed both.
    public let support: Int
    /// Commits in the window that changed the first.
    public let changesA: Int
    /// Commits in the window that changed the second.
    public let changesB: Int
}

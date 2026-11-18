//
//  RollupScope.swift
//  SwiftStatsCore
//
//  What a roll-up summarises (PRD §7.2).
//

/// The records a roll-up covers.
public enum RollupScope: String, Codable, Sendable {
    /// One module (target).
    case module
    /// Every production module, or every test module, of the package.
    case project
}

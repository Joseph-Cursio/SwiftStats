//
//  Lockfile.swift
//  SwiftStatsCore
//
//  The pins in `Package.resolved` (PRD §7.14).
//

/// `Package.resolved`'s pins.
public struct Lockfile: Codable, Hashable, Sendable {
    /// The pins, sorted by identity.
    public let pins: [DependencyPin]

    /// Creates a lockfile. Fields are documented on their properties.
    public init(pins: [DependencyPin]) {
        self.pins = pins
    }
}

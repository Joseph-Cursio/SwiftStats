//
//  USRChange.swift
//  SwiftStatsCore
//
//  A matched record whose key stayed but whose primary USR changed (M7,
//  design §3.6, §10.3): what the spelled name denotes is another
//  declaration to the compiler, such as a typealias retargeted or a type
//  moved to another module. A fact listed under its family, never a delta.
//

/// One record's primary USR before and after, under the same key.
public struct USRChange: Codable, Hashable, Sendable {
    /// The record's key, the same on both sides.
    public let key: String
    /// Its primary USR in the older snapshot.
    public let before: String
    /// Its primary USR in the newer snapshot.
    public let after: String
}

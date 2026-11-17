//
//  ToolInfo.swift
//  SwiftStatsCore
//
//  Which build of SwiftStats produced a scan (PRD §6.2).
//

/// The tool that produced a scan.
public struct ToolInfo: Codable, Hashable, Sendable {
    /// This build of SwiftStats.
    public static let current = Self(name: "swiftstats", version: SwiftStatsVersion.current)

    /// Always `swiftstats`.
    public let name: String
    /// The SwiftStats version.
    public let version: String

    /// Creates tool information.
    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

//
//  CollectorStatus.swift
//  SwiftStatsCore
//
//  One collector's run (PRD §6.5): which tool, which version, with what
//  options, and how it went.
//

/// One collector's run.
public struct CollectorStatus: Codable, Hashable, Sendable {
    /// The collector: `swiftprojectlint`, `swiftlint`, `swifteffectinference`,
    /// `dependencies` or `history`.
    public let name: String
    /// How the run went.
    public let state: CollectorState
    /// The tool's own version string, when it ran.
    public let version: String?
    /// Why it was skipped or how it failed; nil when it ran cleanly.
    public let reason: String?
    /// What it was run with: arguments and configuration, in order.
    public let options: [String]

    /// Creates a status. Fields are documented on their properties.
    public init(name: String, state: CollectorState, version: String?, reason: String?, options: [String]) {
        self.name = name
        self.state = state
        self.version = version
        self.reason = reason
        self.options = options
    }
}

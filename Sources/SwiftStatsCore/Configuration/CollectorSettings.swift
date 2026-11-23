//
//  CollectorSettings.swift
//  SwiftStatsCore
//
//  One `collectors.<name>` entry of `.swiftstats.yml` (PRD §10.1).
//

/// How `.swiftstats.yml` configures one collector.
public struct CollectorSettings: Hashable, Sendable {
    /// Whether the collector runs (`enabled`, default true).
    public let enabled: Bool
    /// The tool's executable (`path`), relative to the package root or
    /// absolute; nil to look it up on PATH.
    public let path: String?
    /// What the collector adds to its tests' command (`arguments`): only
    /// the coverage and swiftmutator collectors take any, and only
    /// `--skip <regex>` pairs.
    public let arguments: [String]
    /// SwiftMutator's `--workers` (`options.workers`, swiftmutator only);
    /// nil for SwiftMutator's own choice.
    public let workers: Int?
    /// SwiftMutator's `--timeout` in seconds, per mutant (`options.timeout`,
    /// swiftmutator only); nil for SwiftMutator's own choice.
    public let timeout: Double?

    /// Settings. Fields are documented on their properties.
    public init(
        enabled: Bool,
        path: String?,
        arguments: [String] = [],
        workers: Int? = nil,
        timeout: Double? = nil
    ) {
        self.enabled = enabled
        self.path = path
        self.arguments = arguments
        self.workers = workers
        self.timeout = timeout
    }
}

//
//  CollectorRunInfo.swift
//  SwiftStatsCore
//
//  What a snapshot records about one collector's run (PRD §6.2, §6.5).
//

/// One collector's run in a snapshot.
public struct CollectorRunInfo: Codable, Hashable, Sendable {
    /// The collector: `swiftstats`, or one a scan reports (`CollectorStatus.name`).
    public let name: String
    /// How the run went.
    public let state: CollectorState
    /// Why it was skipped or how it failed; nil when it ran cleanly.
    public let reason: String?
    /// The tool's own version string, when it ran.
    public let version: String?
    /// The build identity `diff` compares; nil when the tool didn't run.
    public let identity: String?
    /// The commit the build came from, as a label; nil when unknown.
    public let identityLabel: String?
    /// What it was run with, in order.
    public let options: [String]
    /// Wall-clock milliseconds.
    public let durationMilliseconds: Int

    /// Creates a run. Fields are documented on their properties.
    public init(
        name: String,
        state: CollectorState,
        reason: String?,
        version: String?,
        identity: String?,
        identityLabel: String?,
        options: [String],
        durationMilliseconds: Int
    ) {
        self.name = name
        self.state = state
        self.reason = reason
        self.version = version
        self.identity = identity
        self.identityLabel = identityLabel
        self.options = options
        self.durationMilliseconds = durationMilliseconds
    }
}

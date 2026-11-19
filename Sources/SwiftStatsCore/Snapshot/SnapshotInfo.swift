//
//  SnapshotInfo.swift
//  SwiftStatsCore
//
//  A snapshot's metadata (PRD §6.2): which state of which package, when,
//  with what toolchain, and each collector's run.
//

/// What a snapshot records beside its measurements.
public struct SnapshotInfo: Codable, Hashable, Sendable {
    /// The package name from `Package.swift`.
    public let package: String
    /// Where the package was in git.
    public let git: GitState
    /// When the scan was made: ISO 8601, UTC, whole seconds.
    public let date: String
    /// The toolchain in use.
    public let toolchain: Toolchain
    /// Each collector's run, `swiftstats` included, sorted by name.
    public let collectors: [CollectorRunInfo]

    /// Creates snapshot metadata. Fields are documented on their properties.
    public init(package: String, git: GitState, date: String, toolchain: Toolchain, collectors: [CollectorRunInfo]) {
        self.package = package
        self.git = git
        self.date = date
        self.toolchain = toolchain
        self.collectors = collectors
    }
}

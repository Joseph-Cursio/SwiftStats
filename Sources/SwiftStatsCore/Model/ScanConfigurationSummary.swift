//
//  ScanConfigurationSummary.swift
//  SwiftStatsCore
//
//  What the configuration changed in a scan, so a reader can see that
//  files were left out and why (PRD §10.1).
//

/// The configuration a scan ran with, and what it excluded.
public struct ScanConfigurationSummary: Codable, Hashable, Sendable {
    /// The `excluded` globs, as written.
    public let excluded: [String]
    /// Files SwiftPM compiles that the globs left out, sorted.
    public let excludedFiles: [String]
    /// The globs that mark files as generated: `generated` from
    /// `.swiftstats.yml`, or the defaults (PRD D8).
    public let generated: [String]

    /// Creates a summary. Fields are documented on their properties.
    public init(excluded: [String], excludedFiles: [String], generated: [String]) {
        self.excluded = excluded
        self.excludedFiles = excludedFiles
        self.generated = generated
    }
}

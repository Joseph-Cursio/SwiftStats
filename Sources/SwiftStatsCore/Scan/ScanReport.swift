//
//  ScanReport.swift
//  SwiftStatsCore
//
//  The output of `swiftstats scan` (PRD M0, M1a): the package's function,
//  type and file records, their roll-ups, and the Sitrep-compatible counts.
//  It holds no timestamps or absolute paths, so scanning the same tree twice
//  gives byte-identical JSON.
//

/// The result of scanning one package.
public struct ScanReport: Codable, Hashable, Sendable {
    /// The version of this output format. Bumped on any change a reader
    /// would notice: 2 adds complexity, size and shape (M1a); 3 adds
    /// generated files, findings, risk markers, API surface, the test
    /// inventory and dependencies (M1b).
    public static let currentSchemaVersion = 3

    /// The output format version (`currentSchemaVersion` when written).
    public let schemaVersion: Int
    /// The tool that wrote the report.
    public let tool: ToolInfo
    /// The SwiftCodeMetrics versions behind the complexity scores.
    public let metrics: MetricsInfo
    /// The package name from `Package.swift`.
    public let package: String
    /// What `.swiftstats.yml` excluded.
    public let configuration: ScanConfigurationSummary
    /// The scanned targets, sorted by name.
    public let targets: [TargetSummary]
    /// Function records, sorted by file, then position, then key.
    public let records: [FunctionRecord]
    /// Type records, sorted by file, then position.
    public let types: [TypeRecord]
    /// File records, sorted by path.
    public let files: [FileRecord]
    /// Size, shape and complexity per module and for the project.
    public let rollups: [Rollup]
    /// Sitrep-compatible project counts (PRD §7.1).
    public let sitrep: SitrepReport
    /// Non-fatal problems, sorted.
    public let warnings: [ScanWarning]
}

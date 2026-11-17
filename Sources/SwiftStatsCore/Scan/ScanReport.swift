//
//  ScanReport.swift
//  SwiftStatsCore
//
//  The output of `swiftstats scan` (PRD M0): the package's function records
//  and the Sitrep-compatible counts. It holds no timestamps or absolute
//  paths, so scanning the same tree twice gives byte-identical JSON.
//

/// The result of scanning one package.
public struct ScanReport: Codable, Hashable, Sendable {
    /// The version of this output format. Bumped on any change a reader
    /// would notice.
    public static let currentSchemaVersion = 1

    /// The output format version (`currentSchemaVersion` when written).
    public let schemaVersion: Int
    /// The tool that wrote the report.
    public let tool: ToolInfo
    /// The package name from `Package.swift`.
    public let package: String
    /// The scanned targets, sorted by name.
    public let targets: [TargetSummary]
    /// Function records, sorted by file, then position, then key.
    public let records: [FunctionRecord]
    /// Sitrep-compatible project counts (PRD §7.1).
    public let sitrep: SitrepReport
    /// Non-fatal problems, sorted.
    public let warnings: [ScanWarning]

    /// Creates a report. Fields are documented on their properties.
    public init(
        schemaVersion: Int,
        tool: ToolInfo,
        package: String,
        targets: [TargetSummary],
        records: [FunctionRecord],
        sitrep: SitrepReport,
        warnings: [ScanWarning]
    ) {
        self.schemaVersion = schemaVersion
        self.tool = tool
        self.package = package
        self.targets = targets
        self.records = records
        self.sitrep = sitrep
        self.warnings = warnings
    }
}

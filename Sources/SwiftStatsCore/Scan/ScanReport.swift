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
    /// inventory and dependencies (M1b); 4 adds each function's body lines
    /// (M2); 5 adds history (M3); 6 adds side effects, conformances, law
    /// checks, property-test suggestions and clones (M4); 7 adds the
    /// coverage collector (M5).
    public static let currentSchemaVersion = 7

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
    /// Each external collector's run, sorted by name (PRD §6.5).
    public let collectors: [CollectorStatus]
    /// Every finding, sorted by first location, then tool and rule (PRD §7.16).
    public let findings: [Finding]
    /// The test inventory, sorted by file, then key (PRD §7.8).
    public let tests: [TestRecord]
    /// Direct dependencies, pins and the resolved graph (PRD §7.14).
    public let dependencies: DependencyReport
    /// Non-fatal problems, sorted.
    public let warnings: [ScanWarning]
    /// What the side-effect run produced beyond each record's facts; absent
    /// when SwiftEffectInference didn't run (PRD §7.10).
    public let effects: EffectSummary?
    /// SwiftInferProperties' suggestions, attached to records; absent when
    /// it didn't run (PRD §7.11).
    public let properties: PropertyReport?
    /// SwiftCloneDetector's clone classes in the production files, attached
    /// to records; absent when it didn't run (PRD §7.12).
    public let clones: CloneReport?
    /// Law checks per production conformance; always present (PRD §7.11).
    public let laws: LawReport
    /// What the history collector found; absent when it didn't run (PRD §7.13).
    public internal(set) var history: HistoryReport?

    /// The report with `history` attached and the history collector's
    /// status replaced by `status`.
    func with(history: HistoryReport?, status: CollectorStatus) -> Self {
        var report = Self(
            schemaVersion: schemaVersion,
            tool: tool,
            metrics: metrics,
            package: package,
            configuration: configuration,
            targets: targets,
            records: records,
            types: types,
            files: files,
            rollups: rollups,
            sitrep: sitrep,
            collectors: (collectors.filter { $0.name != status.name } + [status]).sorted { $0.name < $1.name },
            findings: findings,
            tests: tests,
            dependencies: dependencies,
            warnings: warnings,
            effects: effects,
            properties: properties,
            clones: clones,
            laws: laws
        )
        report.history = history
        return report
    }
}

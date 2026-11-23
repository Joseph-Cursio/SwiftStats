//
//  ScanReport.swift
//  SwiftStatsCore
//
//  The output of `swiftstats scan` (PRD M0, M1a): the package's function,
//  type and file records, their roll-ups, the Sitrep-compatible counts and
//  what each collector found.
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
    /// coverage collector, its coverage mapped to records and rolled up,
    /// and each record's access level and owning type (M5); 8 adds each
    /// file's SHA-256 and the SwiftMutator collector, whose status every
    /// scan lists (M6).
    public static let currentSchemaVersion = 8

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
    /// The coverage collector's results, mapped to records; absent when it
    /// didn't run (M5, PRD §7.8).
    public let coverage: CoverageReport?
    /// What the history collector found; absent when it didn't run (PRD §7.13).
    public internal(set) var history: HistoryReport?

    /// The report with `history` attached and the history collector's
    /// status replaced by `status`.
    func with(history: HistoryReport?, status: CollectorStatus) -> Self {
        var report = replacing(status, rollups: rollups, coverage: coverage, warnings: warnings)
        report.history = history
        return report
    }

    /// The report with `coverage` attached, the coverage collector's status
    /// replaced by `status`, the roll-ups' coverage rebuilt from it and
    /// `added` among its warnings, once each (M5): how a scan that didn't
    /// run the coverage collector carries coverage an earlier scan of the
    /// same tree collected, with the warnings mapping it gave.
    func with(coverage: CoverageReport, status: CollectorStatus, warnings added: [ScanWarning]) -> Self {
        let plain = rollups.map { $0.with(coverage: nil) }
        let built = CoverageRollupBuilder(targets: targets, records: records, coverage: coverage).rollups(plain)
        let merged = (warnings + added.filter { warnings.contains($0) == false })
            .sorted(by: PackageScanner.warningOrder)
        var report = replacing(status, rollups: built, coverage: coverage, warnings: merged)
        report.history = history
        return report
    }

    /// The report with `status` replacing its collector's status, and
    /// `rollups`, `coverage` and `warnings` replacing its own, and no
    /// history.
    private func replacing(
        _ status: CollectorStatus,
        rollups: [Rollup],
        coverage: CoverageReport?,
        warnings: [ScanWarning]
    ) -> Self {
        Self(
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
            laws: laws,
            coverage: coverage
        )
    }
}

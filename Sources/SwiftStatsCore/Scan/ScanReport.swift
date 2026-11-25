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
    /// scan lists and whose results are mapped to records (M6); 9 adds the
    /// T1 group's collectors, `build`, `index` and `periphery`, whose
    /// statuses every scan lists, the build's type-check timings mapped to
    /// records and its warnings as `swiftc` findings, the index's USRs,
    /// referrers and coupling (module edges, types, USR type cycles, family
    /// references), rolled up for every scope, and outskirts' dead code
    /// mapped to records, with each line ratio's dead lines (M7).
    public static let currentSchemaVersion = 9

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
    public internal(set) var rollups: [Rollup]
    /// Sitrep-compatible project counts (PRD §7.1).
    public let sitrep: SitrepReport
    /// Each external collector's run, sorted by name (PRD §6.5).
    public let collectors: [CollectorStatus]
    /// Every finding, sorted by first location, then tool and rule (PRD §7.16).
    public internal(set) var findings: [Finding]
    /// The test inventory, sorted by file, then key (PRD §7.8).
    public let tests: [TestRecord]
    /// Direct dependencies, pins and the resolved graph (PRD §7.14).
    public let dependencies: DependencyReport
    /// Non-fatal problems, sorted.
    public internal(set) var warnings: [ScanWarning]
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
    /// The SwiftMutator collector's results, mapped to records; absent when
    /// it didn't run or left no results (M6, design §3).
    public let mutation: MutationReport?
    /// The T1 build's type-check timings, mapped to records, and the
    /// counts of what it left out; absent when the `build` collector
    /// didn't run (M7, design §6, §9.2). Its warnings are `swiftc`
    /// findings.
    public internal(set) var build: BuildReport?
    /// The `index` collector's results from the T1 build's index store:
    /// its units, the records' USRs and the reasons some have none, the
    /// USR lists, the records' referrers, the module edges, the types with
    /// their fan-in and cycles, the family references and the files hashed
    /// after the build; absent when the collector didn't run (M7, design
    /// §2–§4, §9.2).
    public internal(set) var index: IndexReport?
    /// The `periphery` collector's results: outskirts' two runs, every
    /// entry with its class and place, the records the unused production
    /// entries cover and each run's dead lines per module; absent when the
    /// collector didn't run (M7, design §5, §9.2).
    public internal(set) var deadCode: DeadCodeReport?
    /// What the history collector found; absent when it didn't run (PRD §7.13).
    public internal(set) var history: HistoryReport?

    /// The report with `history` attached and the history collector's
    /// status replaced by `status`.
    func with(history: HistoryReport?, status: CollectorStatus) -> Self {
        var report = replacing(status, rollups: rollups, coverage: coverage, mutation: mutation, warnings: warnings)
        report.history = history
        return report
    }

    /// The report with `build` attached, the `build` collector's status
    /// replaced by `status` and the roll-ups' type-check figures rebuilt
    /// from it with `totals` as each scope's total (M7, design §6.4): how
    /// the scan attaches its T1 build's mapped timings, whose warnings are
    /// already among the findings and counted in the roll-ups, so a fresh
    /// scan and a carried one roll them up alike. A nil `build` leaves
    /// every roll-up without type-check figures.
    func with(build: BuildReport?, totals: TypeCheckTotals, status: CollectorStatus) -> Self {
        let plain = rollups.map { $0.with(typecheck: nil) }
        let built = build.map { held in
            TypeCheckRollupBuilder(targets: targets, records: records, report: held, totals: totals).rollups(plain)
        }
        var report = replacing(
            status,
            rollups: built ?? plain,
            coverage: coverage,
            mutation: mutation,
            warnings: warnings
        )
        report.build = build
        report.history = history
        return report
    }

    /// The report with the T1 `group`'s build, index and dead-code results
    /// attached and their collectors' statuses replaced.
    func with(_ group: PackageScanner.IndexGroup) -> Self {
        with(build: group.report, totals: group.typeCheckTotals, status: group.build.result.status)
            .with(index: group.indexReport, status: group.indexStatus)
            .with(deadCode: group.deadCodeReport, status: group.peripheryStatus)
    }

    /// The report with `deadCode` attached, the `periphery` collector's
    /// status replaced by `status`, and the roll-ups' dead-code counts and
    /// line ratios' dead lines rebuilt from it (M7, design §7): how a scan
    /// attaches its dead-code results, so a fresh scan and a carried one
    /// roll them up alike. A nil `deadCode` leaves every roll-up without
    /// dead-code counts and every line ratio without dead lines, dead code
    /// not excluded.
    func with(deadCode: DeadCodeReport?, status: CollectorStatus) -> Self {
        let plain = rollups.map { $0.with(deadCode: nil).with(deadLines: nil) }
        let built = deadCode.map { report in
            DeadCodeRollupBuilder(targets: targets, records: records, report: report).rollups(plain)
        }
        var report = replacing(
            status,
            rollups: built ?? plain,
            coverage: coverage,
            mutation: mutation,
            warnings: warnings
        )
        report.deadCode = deadCode
        report.history = history
        return report
    }

    /// The report with `index` attached, the `index` collector's status
    /// replaced by `status` and the roll-ups' USR counts rebuilt from it
    /// (M7): how a scan attaches its index results, so a fresh scan and a
    /// carried one roll them up alike. A nil `index` leaves every roll-up
    /// without USR counts.
    func with(index: IndexReport?, status: CollectorStatus) -> Self {
        let plain = rollups.map { $0.with(index: nil) }
        let built = index.map { IndexRollupBuilder(targets: targets, records: records, report: $0).rollups(plain) }
        var report = replacing(
            status,
            rollups: built ?? plain,
            coverage: coverage,
            mutation: mutation,
            warnings: warnings
        )
        report.index = index
        report.history = history
        return report
    }

    /// The report with `added` as tool `tool`'s findings, replacing any it
    /// held, and every roll-up's counts of them rebuilt as a scan counts
    /// the findings of a tool that ran (M7, design §9.4): how a scan
    /// carrying T1 results keeps the build's warnings, `swiftc` findings
    /// already attached to the same records and places.
    func with(findings added: [Finding], of tool: String) -> Self {
        var report = self
        report.findings = (findings.filter { $0.tool != tool } + added).sorted(by: PackageScanner.findingOrder)
        let tally = FindingTally(findings: added, tools: [tool])
        report.rollups = rollups.map { rollup in
            let modules = RollupBuilder.modules(of: rollup, targets: targets)
            let paths = Set(files.filter { modules.contains($0.module) }.map(\.path))
            return rollup.with(
                findings: tally.byRule(in: paths)[tool] ?? [:],
                kinds: tally.byKind(in: paths)[tool] ?? [:],
                of: tool
            )
        }
        return report
    }

    /// The report with `added` among its warnings, once each, sorted as a
    /// scan sorts them.
    func with(warnings added: [ScanWarning]) -> Self {
        var report = self
        report.warnings = (warnings + added.filter { warnings.contains($0) == false })
            .sorted(by: PackageScanner.warningOrder)
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
        var report = replacing(status, rollups: built, coverage: coverage, mutation: mutation, warnings: merged)
        report.history = history
        return report
    }

    /// The report with `mutation` attached, the SwiftMutator collector's
    /// status replaced by `status`, the roll-ups' mutation results rebuilt
    /// from it and `added` among its warnings, once each (M6, design §6.4):
    /// how a scan that didn't run the SwiftMutator collector carries the
    /// results an earlier scan of the same tree collected, with the
    /// warnings mapping them gave.
    func with(mutation: MutationReport, status: CollectorStatus, warnings added: [ScanWarning]) -> Self {
        let plain = rollups.map { $0.with(mutation: nil) }
        let built = MutationRollupBuilder(targets: targets, records: records, files: files, report: mutation)
            .rollups(plain)
        let merged = (warnings + added.filter { warnings.contains($0) == false })
            .sorted(by: PackageScanner.warningOrder)
        var report = replacing(status, rollups: built, coverage: coverage, mutation: mutation, warnings: merged)
        report.history = history
        return report
    }

    /// The report with `status` replacing its collector's status, and
    /// `rollups`, `coverage`, `mutation` and `warnings` replacing its own,
    /// its build, index and dead-code results kept, and no history.
    private func replacing(
        _ status: CollectorStatus,
        rollups: [Rollup],
        coverage: CoverageReport?,
        mutation: MutationReport?,
        warnings: [ScanWarning]
    ) -> Self {
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
            laws: laws,
            coverage: coverage,
            mutation: mutation
        )
        report.build = build
        report.index = index
        report.deadCode = deadCode
        return report
    }
}

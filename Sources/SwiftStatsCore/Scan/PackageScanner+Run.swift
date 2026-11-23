//
//  PackageScanner+Run.swift
//  SwiftStatsCore
//
//  The scan itself (PRD M0–M2, M4–M6): describe the package, start
//  SwiftInferProperties and, when asked for, the coverage run, measure its
//  files, infer side effects, run the other external collectors,
//  SwiftCloneDetector among them, then, when asked for, SwiftMutator alone,
//  attach the suggestions and clones and assemble the report, timing each
//  collector for the snapshot (PRD §6.2).
//

import Foundation

extension PackageScanner {
    /// The roll-ups of `measured` over `targets`, with `external`'s findings,
    /// SwiftInferProperties' suggestions, SwiftCloneDetector's classes and
    /// the coverage counted.
    private static func rollups(
        _ targets: [TargetSummary],
        measured: ScanMeasurements,
        external: ExternalScan
    ) -> [Rollup] {
        let rollups = RollupBuilder.rollups(
            targets: targets,
            input: RollupInput(
                records: measured.records,
                types: measured.types,
                files: measured.files,
                declarations: measured.declarations,
                tests: measured.tests,
                findings: external.tally,
                effectsCollected: measured.effectsCollected,
                laws: measured.laws.checks,
                properties: external.properties,
                clones: external.clones
            )
        )
        guard let coverage = external.coverage else {
            return rollups
        }
        return CoverageRollupBuilder(targets: targets, records: measured.records, coverage: coverage).rollups(rollups)
    }

    /// Every collector's status but history's real one, sorted by name.
    private static func statuses(
        _ adapters: [AdapterResult],
        effects: EffectScan,
        dependencies: DependencyScan
    ) -> [CollectorStatus] {
        (adapters.map(\.status) + [effects.status, dependencies.status, HistoryCollector.notRequested])
            .sorted { $0.name < $1.name }
    }

    /// A warning for each Swift file under `Tests/Generated/` of the
    /// package at `root` that no target of `package` compiles.
    private static func unbuiltTests(_ package: DescribedPackage, root: URL) -> [ScanWarning] {
        UnbuiltTests.warnings(root: root, compiled: Set(TargetResolver.resolve(package).flatMap(\.files)))
    }

    /// Throws `ScanError.notAPackage` unless `root` holds a `Package.swift`.
    private static func requirePackage(at root: URL) throws {
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) else {
            throw ScanError.notAPackage(root.path)
        }
    }

    /// The scan of `packageRoot`, with each collector's run time and binary;
    /// the coverage and SwiftMutator collectors run only when `tiers` asks
    /// for them.
    func run(packageAt packageRoot: URL, configurationFile: URL?, tiers: RequestedTiers) throws -> ScanOutcome {
        let root = packageRoot.standardizedFileURL
        try Self.requirePackage(at: root)
        let configuration = try SwiftStatsConfiguration.load(configurationFile, root: root)
        let package = try describer.describePackage(at: root)
        let (targets, excludedFiles) = Self.excluding(TargetResolver.resolve(package), by: configuration)
        let pending = startBackground(root: root, targets: targets, configuration: configuration, tiers: tiers)
        let scan = Self.measured(targets, root: root, configuration: configuration)
        let (measured, effects) = (scan.measurements, scan.effects)
        let external = externalRuns(
            root: root,
            targets: targets,
            configuration: configuration,
            pending: pending,
            measured: measured
        )
        let dependencies = dependencies(of: package, root: root, configuration: configuration)
        let warnings = measured.warnings + Self.unusedKeyWarnings(configuration) + external.warnings
            + Self.unbuiltTests(package, root: root) + dependencies.warnings
        let report = ScanReport(
            schemaVersion: ScanReport.currentSchemaVersion,
            tool: .current,
            metrics: measured.metrics,
            package: package.name,
            configuration: ScanConfigurationSummary(configuration, excludedFiles: excludedFiles),
            targets: targets,
            records: measured.records.sorted(by: Self.recordOrder),
            types: measured.types.sorted(by: Self.typeOrder),
            files: measured.files.sorted { $0.path < $1.path },
            rollups: Self.rollups(targets, measured: measured, external: external),
            sitrep: measured.sitrep,
            collectors: Self.statuses(external.adapters, effects: effects, dependencies: dependencies),
            findings: external.findings.sorted(by: Self.findingOrder),
            tests: measured.tests.sorted { ($0.file, $0.key) < ($1.file, $1.key) },
            dependencies: dependencies.report,
            warnings: warnings.sorted(by: Self.warningOrder),
            effects: effects.summary,
            properties: external.properties,
            clones: external.clones?.report,
            laws: measured.laws.with(kitDependency: KitProtocols.isDependency(in: dependencies.report)),
            coverage: external.coverage
        )
        return ScanOutcome(
            report: report,
            configuration: configuration,
            measureMilliseconds: scan.milliseconds,
            adapters: external.timed,
            effects: effects,
            dependencies: dependencies
        )
    }
}

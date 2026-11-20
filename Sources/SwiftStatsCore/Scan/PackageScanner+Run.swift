//
//  PackageScanner+Run.swift
//  SwiftStatsCore
//
//  The scan itself (PRD M0–M2, M4): describe the package, measure its files,
//  infer side effects, run the external collectors and assemble the report,
//  timing each collector for the snapshot (PRD §6.2).
//

import Foundation

extension PackageScanner {
    /// The roll-ups of `measured` over `targets`, with `findings` counted.
    private static func rollups(
        _ targets: [TargetSummary],
        measured: ScanMeasurements,
        findings: FindingTally
    ) -> [Rollup] {
        RollupBuilder.rollups(
            targets: targets,
            input: RollupInput(
                records: measured.records,
                types: measured.types,
                files: measured.files,
                declarations: measured.declarations,
                tests: measured.tests,
                findings: findings,
                effectsCollected: measured.effectsCollected
            )
        )
    }
    /// The scan of `packageRoot`, with each collector's run time and binary.
    func run(packageAt packageRoot: URL, configurationFile: URL?) throws -> ScanOutcome {
        let root = packageRoot.standardizedFileURL
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) else {
            throw ScanError.notAPackage(root.path)
        }
        let configuration = try SwiftStatsConfiguration.load(configurationFile, root: root)
        let package = try describer.describePackage(at: root)
        let (targets, excludedFiles) = Self.excluding(TargetResolver.resolve(package), by: configuration)
        let scan = Self.measured(targets, root: root, configuration: configuration)
        let (measured, effects) = (scan.measurements, scan.effects)
        let timed = toolSkipReason.map(CollectorRun.skipped)
            ?? CollectorRun.run(root: root, targets: targets, configuration: configuration, locator: tools)
        let adapters = timed.map(\.result)
        let findings = Self.attach(measured.markers + adapters.flatMap(\.findings), to: measured)
        let ranTools = Set(adapters.filter { $0.status.state == .ran }.map(\.status.name)).union([MarkerCollector.tool])
        let compiled = Set(TargetResolver.resolve(package).flatMap(\.files))
        let dependencies = dependencies(of: package, root: root, configuration: configuration)
        let warnings = measured.warnings + Self.unusedKeyWarnings(configuration) + adapters.flatMap(\.warnings)
            + UnbuiltTests.warnings(root: root, compiled: compiled) + dependencies.warnings
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
            rollups: Self.rollups(
                targets,
                measured: measured,
                findings: FindingTally(findings: findings, tools: ranTools)
            ),
            sitrep: measured.sitrep,
            collectors: (adapters.map(\.status) + [effects.status, dependencies.status, HistoryCollector.notRequested])
                .sorted { $0.name < $1.name },
            findings: findings.sorted(by: Self.findingOrder),
            tests: measured.tests.sorted { ($0.file, $0.key) < ($1.file, $1.key) },
            dependencies: dependencies.report,
            warnings: warnings.sorted(by: Self.warningOrder),
            effects: effects.summary
        )
        return ScanOutcome(
            report: report,
            configuration: configuration,
            measureMilliseconds: scan.milliseconds,
            adapters: timed,
            effects: effects,
            dependencies: dependencies
        )
    }
}

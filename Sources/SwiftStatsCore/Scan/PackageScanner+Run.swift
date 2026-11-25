//
//  PackageScanner+Run.swift
//  SwiftStatsCore
//
//  The scan itself (PRD M0–M2, M4–M7): describe the package, start
//  SwiftInferProperties and, when asked for, the coverage run, measure its
//  files, infer side effects, run the other external collectors,
//  SwiftCloneDetector among them, then, when asked for, the T1 group
//  (`scan --index`) alone and SwiftMutator alone, attach the suggestions,
//  the clones and the build's timings and assemble the report, timing each
//  collector for the snapshot (PRD §6.2).
//

import Foundation

extension PackageScanner {
    /// The roll-ups of `measured` over `targets`, with `external`'s findings,
    /// SwiftInferProperties' suggestions, SwiftCloneDetector's classes, the
    /// coverage and the mutation results counted.
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
        let covered = external.coverage.map { coverage in
            CoverageRollupBuilder(targets: targets, records: measured.records, coverage: coverage).rollups(rollups)
        } ?? rollups
        guard let mutation = external.mutationReport else {
            return covered
        }
        return MutationRollupBuilder(
            targets: targets,
            records: measured.records,
            files: measured.files,
            report: mutation
        ).rollups(covered)
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

    /// `packageRoot`, standardized; throws `ScanError.notAPackage` unless
    /// it holds a `Package.swift`.
    private static func requiredRoot(_ packageRoot: URL) throws -> URL {
        let root = packageRoot.standardizedFileURL
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) else {
            throw ScanError.notAPackage(root.path)
        }
        return root
    }

    /// The scan of `packageRoot`, with each collector's run time and binary;
    /// the coverage collector, the T1 group and the SwiftMutator collector
    /// run only when `tiers` asks for them. SwiftMutator's copy checks out
    /// the commit of `git`, the package's state as read before the scan
    /// (read when it runs when nil), and leaves out the files at
    /// `ignoring`; a `--since` run, or the resume of one, merges with the
    /// base `tiers` carries. For a scan that stores its snapshot,
    /// `indexSaving`'s gate runs before the T1 build starts and `saving`'s
    /// before SwiftMutator starts, and either may stop the scan.
    func run(
        packageAt packageRoot: URL,
        configurationFile: URL?,
        tiers: RequestedTiers,
        git: GitState?,
        ignoring: [String]
    ) throws -> ScanOutcome {
        let root = try Self.requiredRoot(packageRoot)
        let configuration = try SwiftStatsConfiguration.load(configurationFile, root: root)
        let package = try describer.describePackage(at: root)
        let (targets, excludedFiles) = Self.excluding(TargetResolver.resolve(package), by: configuration)
        var pending = startBackground(root: root, targets: targets, configuration: configuration, tiers: tiers)
        pending.prepareMutation(git: git, ignoring: ignoring, saving: saving, indexSaving: indexSaving)
        let scan = Self.measured(targets, root: root, configuration: configuration)
        let (measured, effects) = (scan.measurements, scan.effects)
        let external = try externalRuns(
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
            coverage: external.coverage,
            mutation: external.mutationReport
        ).with(external.index)
        return ScanOutcome(
            report: report,
            configuration: configuration,
            measureMilliseconds: scan.milliseconds,
            adapters: external.timed,
            effects: effects,
            dependencies: dependencies
        )
    }

    /// The same scanner, its external tool adapters skipped for `reason`,
    /// or run when it is nil; everything else it was given is kept (a
    /// backfill scans with it).
    func skippingTools(for reason: String?) -> Self {
        var scanner = self
        scanner.toolSkipReason = reason
        return scanner
    }
}

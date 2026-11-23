//
//  PackageScanner+Properties.swift
//  SwiftStatsCore
//
//  The external collectors' part of a scan (PRD §7.16, §7.11):
//  SwiftInferProperties is started before the package is measured, since it
//  needs only the package's files, and waited for once the other external
//  collectors have run, when its suggestions are attached to the measured
//  records, joined to the package's own decisions and verify evidence and
//  linked to property tests, and every finding is attached to its place.
//  SwiftCloneDetector starts beside the other external collectors and is
//  waited for with them, as is the coverage run when the scan asked for it;
//  the SwiftMutator run, when asked for, follows them alone. The tools'
//  skip reason covers all of them.
//

import Foundation

extension PackageScanner {
    /// The collectors started in the background before the package is
    /// measured, waited for with the other external collectors, and the
    /// SwiftMutator run asked for, which follows them.
    struct PendingRuns {
        /// SwiftInferProperties' run; nil when the tools are skipped.
        let properties: BackgroundJob<SwiftInferRun>?
        /// The coverage run, or its skip.
        let coverage: BackgroundJob<CoverageRun>
        /// The SwiftMutator run the scan asked for; nil when it didn't.
        let mutation: MutationRequest?
    }

    /// The external collectors' part of a scan.
    struct ExternalScan {
        /// Each external collector's run, SwiftInferProperties',
        /// SwiftCloneDetector's, the coverage collector's and the
        /// SwiftMutator collector's included.
        let timed: [TimedAdapterResult]
        /// SwiftStats' markers and the tools' findings, attached.
        let findings: [Finding]
        /// The findings, counted for the tools that ran.
        let tally: FindingTally
        /// SwiftInferProperties' suggestions, attached, joined and linked;
        /// nil unless it ran.
        let properties: PropertyReport?
        /// Problems joining the suggestions to the package's own files.
        let joinWarnings: [ScanWarning]
        /// SwiftCloneDetector's classes, attached; nil unless it ran.
        let clones: CloneMapping?
        /// The coverage run's export, mapped to records; nil unless it ran.
        let coverage: CoverageReport?
        /// Problems mapping the coverage.
        let coverageWarnings: [ScanWarning]

        /// Each external collector's result.
        var adapters: [AdapterResult] {
            timed.map(\.result)
        }

        /// The problems the external collectors reported.
        var warnings: [ScanWarning] {
            adapters.flatMap(\.warnings) + joinWarnings + coverageWarnings
        }
    }

    /// The suggestions of `run` attached to `measured`'s records, joined to
    /// the decisions and verify evidence of the package at `root` and
    /// linked to the property tests among `measured`'s tests and
    /// `findings`' markers; nil unless it ran. The warnings are the joins'.
    static func properties(
        of run: SwiftInferRun,
        measured: ScanMeasurements,
        targets: [TargetSummary],
        root: URL,
        findings: [Finding]
    ) -> (report: PropertyReport?, warnings: [ScanWarning]) {
        guard let merged = run.merged else {
            return (nil, [])
        }
        let mapper = CandidateMapper(measured: measured, testModules: Set(targets.filter(\.isTest).map(\.name)))
        let joins = PropertyJoins(root: root)
        let links = PropertyTestLinks(measured: measured, findings: findings, targets: targets)
        let candidates = mapper.candidates(of: merged) { row, candidate in
            links.linked(joins.joined(candidate, fingerprint: row.subjectFingerprint))
        }
        let orphans = joins.orphans(among: candidates)
        let report = PropertyReport(
            candidates: candidates,
            orphanDecisions: orphans.decisions,
            orphanVerifyRecords: orphans.verifyRecords,
            crossTargetDuplicates: merged.duplicates,
            crossTargetConflicts: merged.conflicts,
            identityCollisions: merged.collisions,
            joinInputs: joins.inputs,
            seiRevision: run.seiRevision
        )
        return (report, joins.warnings)
    }

    /// SwiftInferProperties' run over `targets` of the package at `root`,
    /// and the coverage run when `tiers` asks for it, started in the
    /// background, with the SwiftMutator run `tiers` asks for.
    func startBackground(
        root: URL,
        targets: [TargetSummary],
        configuration: SwiftStatsConfiguration,
        tiers: RequestedTiers
    ) -> PendingRuns {
        PendingRuns(
            properties: startProperties(root: root, targets: targets, configuration: configuration),
            coverage: startCoverage(root: root, configuration: configuration, requested: tiers.coverage),
            mutation: tiers.mutation
        )
    }

    /// SwiftInferProperties' run over `targets` of the package at `root`,
    /// started in the background; nil when the tools are skipped.
    private func startProperties(
        root: URL,
        targets: [TargetSummary],
        configuration: SwiftStatsConfiguration
    ) -> BackgroundJob<SwiftInferRun>? {
        guard toolSkipReason == nil else {
            return nil
        }
        return CollectorRun.startProperties(root: root, targets: targets, configuration: configuration, locator: tools)
    }

    /// Starts SwiftCloneDetector and runs the other external collectors on
    /// `targets` of the package at `root`, waits for it and for `pending`,
    /// SwiftInferProperties' and the coverage collector's runs, then runs
    /// the SwiftMutator collector alone, and attaches the classes, the
    /// suggestions, the coverage and every finding to `measured`'s records.
    func externalRuns(
        root: URL,
        targets: [TargetSummary],
        configuration: SwiftStatsConfiguration,
        pending: PendingRuns,
        measured: ScanMeasurements
    ) -> ExternalScan {
        let cloneJob = startClones(root: root, targets: targets, configuration: configuration, measured: measured)
        let adapters = toolSkipReason.map(CollectorRun.skipped)
            ?? CollectorRun.run(root: root, targets: targets, configuration: configuration, locator: tools)
        let cloneRun = cloneJob?.wait()
        let run = pending.properties?.wait()
        let coverage = pending.coverage.wait()
        let mutation = runMutation(root: root, configuration: configuration, request: pending.mutation)
        let findings = Self.attach(measured.markers + adapters.flatMap(\.result.findings), to: measured)
        // SwiftInferProperties and SwiftCloneDetector report no findings,
        // so they get no counts.
        let ran = adapters.map(\.result.status).filter { $0.state == .ran }.map(\.name)
        let properties = run.map { completed in
            Self.properties(of: completed, measured: measured, targets: targets, root: root, findings: findings)
        }
        let mapped = Self.coverage(
            of: coverage,
            measured: measured,
            targets: targets,
            configuration: configuration,
            root: root
        )
        return ExternalScan(
            timed: adapters + [run?.timed, cloneRun?.timed, coverage.timed].compactMap(\.self) + [mutation],
            findings: findings,
            tally: FindingTally(findings: findings, tools: Set(ran).union([MarkerCollector.tool])),
            properties: properties?.report,
            joinWarnings: properties?.warnings ?? [],
            clones: cloneRun.flatMap { Self.clones(of: $0, measured: measured) },
            coverage: mapped.report,
            coverageWarnings: mapped.warnings
        )
    }
}

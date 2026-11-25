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
//  the T1 group, then the SwiftMutator run, each when asked for, follow
//  them alone. The tools' skip reason covers all of them.
//

import Foundation

extension PackageScanner {
    /// The collectors started in the background before the package is
    /// measured, waited for with the other external collectors, and the
    /// T1 group and the SwiftMutator run asked for, which follow them.
    struct PendingRuns {
        /// SwiftInferProperties' run; nil when the tools are skipped.
        let properties: BackgroundJob<SwiftInferRun>?
        /// The coverage run, or its skip.
        let coverage: BackgroundJob<CoverageRun>
        /// The SwiftMutator run the scan asked for; nil when it didn't.
        var mutation: MutationScope?
        /// Whether the scan asked for the T1 group (`scan --index`), which
        /// runs in the foreground, alone, once the background runs end.
        let index: Bool
        /// What a scan that stores its snapshot checks before its
        /// SwiftMutator run starts (`MutationSaving`); nil for another scan.
        var gate: ((CollectorStatus, [FunctionRecord]) throws -> Void)?

        /// Sets the SwiftMutator run's copy to check out `git`'s commit and
        /// leave out the files at `ignoring`, and, for a scan that stores
        /// its snapshot as `saving` says, its gate and keeping a run that
        /// ran until it is stored.
        mutating func prepareMutation(git: GitState?, ignoring: [String], saving: MutationSaving?) {
            mutation = mutation?.with(git: git, ignoring: ignoring, keepsUntilStored: saving != nil)
            gate = saving?.gate
        }
    }

    /// The external collectors' part of a scan.
    struct ExternalScan {
        /// Each external collector's run, SwiftInferProperties',
        /// SwiftCloneDetector's, the coverage collector's, the T1 group's
        /// (`build`, `index`, `periphery`) and the SwiftMutator collector's
        /// included.
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
        /// The SwiftMutator run, or its skip.
        let mutation: MutationRun
        /// Its results, mapped to records; nil unless it ran with results.
        let mutationReport: MutationReport?
        /// Problems mapping the mutants.
        let mutationWarnings: [ScanWarning]

        /// Each external collector's result.
        var adapters: [AdapterResult] {
            timed.map(\.result)
        }

        /// The problems the external collectors reported.
        var warnings: [ScanWarning] {
            adapters.flatMap(\.warnings) + joinWarnings + coverageWarnings + mutationWarnings
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
    /// background, with the T1 group and the SwiftMutator run `tiers` asks
    /// for, before the scan sets the git state it read and the files the
    /// SwiftMutator copy leaves out.
    func startBackground(
        root: URL,
        targets: [TargetSummary],
        configuration: SwiftStatsConfiguration,
        tiers: RequestedTiers
    ) -> PendingRuns {
        PendingRuns(
            properties: startProperties(root: root, targets: targets, configuration: configuration),
            coverage: startCoverage(root: root, configuration: configuration, requested: tiers.coverage),
            mutation: tiers.mutation.map { MutationScope(request: $0, base: tiers.base, git: nil, ignoring: []) },
            index: tiers.index,
            gate: nil
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
    /// the T1 group alone when `pending` asks for it (and lists it skipped
    /// otherwise), then the SwiftMutator collector alone, and attaches the
    /// classes, the suggestions, the coverage, the mutants and every
    /// finding to `measured`'s records. When a SwiftMutator run was asked
    /// for, `pending`'s gate is given the coverage run's status and the
    /// records before it starts, once every other run has ended, and may
    /// stop the scan.
    func externalRuns(
        root: URL,
        targets: [TargetSummary],
        configuration: SwiftStatsConfiguration,
        pending: PendingRuns,
        measured: ScanMeasurements
    ) throws -> ExternalScan {
        let cloneJob = startClones(root: root, targets: targets, configuration: configuration, measured: measured)
        let adapters = toolSkipReason.map(CollectorRun.skipped)
            ?? CollectorRun.run(root: root, targets: targets, configuration: configuration, locator: tools)
        let cloneRun = cloneJob?.wait()
        let run = pending.properties?.wait()
        let coverage = pending.coverage.wait()
        let indexGroup = runIndexGroup(root: root, configuration: configuration, requested: pending.index)
        if pending.mutation != nil, let gate = pending.gate {
            try gate(coverage.status, measured.records)
        }
        let mutationRun = runMutation(
            root: root,
            configuration: configuration,
            scope: pending.mutation,
            measured: measured
        )
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
        let mappedMutation = Self.mutation(
            of: mutationRun,
            measured: measured,
            targets: targets,
            configuration: configuration
        )
        return ExternalScan(
            timed: adapters + [run?.timed, cloneRun?.timed, coverage.timed].compactMap(\.self) + indexGroup
                + [mappedMutation.run.timed],
            findings: findings,
            tally: FindingTally(findings: findings, tools: Set(ran).union([MarkerCollector.tool])),
            properties: properties?.report,
            joinWarnings: properties?.warnings ?? [],
            clones: cloneRun.flatMap { Self.clones(of: $0, measured: measured) },
            coverage: mapped.report,
            coverageWarnings: mapped.warnings,
            mutation: mappedMutation.run,
            mutationReport: mappedMutation.report,
            mutationWarnings: mappedMutation.warnings
        )
    }
}

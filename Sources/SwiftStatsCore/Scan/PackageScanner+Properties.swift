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
//  The tools' skip reason covers all of them.
//

import Foundation

extension PackageScanner {
    /// The external collectors' part of a scan.
    struct ExternalScan {
        /// Each external collector's run, SwiftInferProperties' included.
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

        /// Each external collector's result.
        var adapters: [AdapterResult] {
            timed.map(\.result)
        }

        /// The problems the external collectors reported.
        var warnings: [ScanWarning] {
            adapters.flatMap(\.warnings) + joinWarnings
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
    /// started in the background; nil when the tools are skipped.
    func startProperties(
        root: URL,
        targets: [TargetSummary],
        configuration: SwiftStatsConfiguration
    ) -> BackgroundJob<SwiftInferRun>? {
        guard toolSkipReason == nil else {
            return nil
        }
        return CollectorRun.startProperties(root: root, targets: targets, configuration: configuration, locator: tools)
    }

    /// Runs the other external collectors on `targets` of the package at
    /// `root`, waits for `pending`, SwiftInferProperties' run, and attaches
    /// its suggestions and every finding to `measured`'s records.
    func externalRuns(
        root: URL,
        targets: [TargetSummary],
        configuration: SwiftStatsConfiguration,
        pending: BackgroundJob<SwiftInferRun>?,
        measured: ScanMeasurements
    ) -> ExternalScan {
        let adapters = toolSkipReason.map(CollectorRun.skipped)
            ?? CollectorRun.run(root: root, targets: targets, configuration: configuration, locator: tools)
        let run = pending?.wait()
        let findings = Self.attach(measured.markers + adapters.flatMap(\.result.findings), to: measured)
        // SwiftInferProperties reports no findings, so it gets no counts.
        let ran = adapters.map(\.result.status).filter { $0.state == .ran }.map(\.name)
        let properties = run.map { completed in
            Self.properties(of: completed, measured: measured, targets: targets, root: root, findings: findings)
        }
        return ExternalScan(
            timed: adapters + [run?.timed].compactMap(\.self),
            findings: findings,
            tally: FindingTally(findings: findings, tools: Set(ran).union([MarkerCollector.tool])),
            properties: properties?.report,
            joinWarnings: properties?.warnings ?? []
        )
    }
}

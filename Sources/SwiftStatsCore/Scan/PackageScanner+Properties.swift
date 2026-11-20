//
//  PackageScanner+Properties.swift
//  SwiftStatsCore
//
//  The external collectors' part of a scan (PRD §7.16, §7.11):
//  SwiftInferProperties is started before the package is measured, since it
//  needs only the package's files, and waited for once the other external
//  collectors have run, when its suggestions are attached to the measured
//  records and every finding to its place. The tools' skip reason covers
//  all of them.
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
        /// SwiftInferProperties' suggestions, attached; nil unless it ran.
        let properties: PropertyReport?

        /// Each external collector's result.
        var adapters: [AdapterResult] {
            timed.map(\.result)
        }

        /// The problems the external collectors reported.
        var warnings: [ScanWarning] {
            adapters.flatMap(\.warnings)
        }
    }

    /// The suggestions of `run` attached to `measured`'s records; nil
    /// unless it ran.
    static func properties(
        of run: SwiftInferRun,
        measured: ScanMeasurements,
        targets: [TargetSummary]
    ) -> PropertyReport? {
        guard let merged = run.merged else {
            return nil
        }
        let mapper = CandidateMapper(measured: measured, testModules: Set(targets.filter(\.isTest).map(\.name)))
        return PropertyReport(
            candidates: mapper.candidates(of: merged),
            crossTargetDuplicates: merged.duplicates,
            crossTargetConflicts: merged.conflicts,
            identityCollisions: merged.collisions,
            seiRevision: run.seiRevision
        )
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
        return ExternalScan(
            timed: adapters + [run?.timed].compactMap(\.self),
            findings: findings,
            tally: FindingTally(findings: findings, tools: Set(ran).union([MarkerCollector.tool])),
            properties: run.flatMap { Self.properties(of: $0, measured: measured, targets: targets) }
        )
    }
}

//
//  PackageScanner+Mutation.swift
//  SwiftStatsCore
//
//  The SwiftMutator collector's part of a scan (M6, design §1). It runs
//  only when the scan asks for it (`scan --mutation`), alone, after every
//  other collector has finished, since SwiftMutator times the package's
//  tests and sets each mutant's time limit from them, so nothing else may
//  compete for the CPU. The tools' skip reason covers a requested run.
//  A run that ran with results is mapped onto the scan's records
//  (`MutationMapper`) and passed through the store's rows
//  (`MutationRows`), so the scan JSON is what a stored copy would give.
//

import Foundation

extension PackageScanner {
    /// `run`'s results mapped onto `measured`, the package with `targets`
    /// and `configuration`, as the store's rows hold them; nil unless it
    /// ran with results. The warnings are the mapping's.
    static func mutation(
        of run: MutationRun,
        measured: ScanMeasurements,
        targets: [TargetSummary],
        configuration: SwiftStatsConfiguration
    ) -> (report: MutationReport?, warnings: [ScanWarning]) {
        guard run.status.state == .ran, let results = run.results, let resultsFile = run.resultsFile else {
            return (nil, [])
        }
        let mapper = MutationMapper(
            measured: measured,
            targets: targets,
            excluded: configuration.excluded.map(GlobPattern.init)
        )
        let record = MutationMapper.run(
            results,
            ordinal: 0,
            resultsFile: resultsFile,
            git: run.git,
            suspects: run.suspects
        )
        let report = mapper.report(of: results, run: record, suspects: run.suspects)
        return (MutationRows.normalized(report), mapper.warnings)
    }

    /// The SwiftMutator collector's run on the package at `root` under
    /// `configuration`, made in the foreground as `scope` asks, its copy
    /// checked against `measured`'s files; a skip when the scan asked for
    /// none or the tools are skipped.
    func runMutation(
        root: URL,
        configuration: SwiftStatsConfiguration,
        scope: MutationScope?,
        measured: ScanMeasurements
    ) -> MutationRun {
        guard let scope else {
            return MutationRun.skipped(MutationAdapter.notRequestedReason)
        }
        if let toolSkipReason {
            return MutationRun.skipped(toolSkipReason)
        }
        return CollectorRun.runMutation(
            root: root,
            configuration: configuration,
            locator: tools,
            scope: scope,
            measured: measured.files
        )
    }
}

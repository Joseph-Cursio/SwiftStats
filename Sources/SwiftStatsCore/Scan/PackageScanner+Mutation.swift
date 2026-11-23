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
//  (`MutationRows`), so the scan JSON is what a stored copy would give; a
//  `--since` run is merged with its base first (`MutationMerge`), and a
//  full run that found no code SwiftMutator could test gives empty
//  results.
//

import Foundation

extension PackageScanner {
    /// A SwiftMutator run's results mapped onto a scan.
    struct MappedMutation {
        /// The run, its reason with a merge's notes added.
        let run: MutationRun
        /// The results, as the store's rows hold them; nil unless the run
        /// ran.
        let report: MutationReport?
        /// The mapping's warnings.
        let warnings: [ScanWarning]
    }

    /// `run`'s results mapped onto `measured`, the package with `targets`
    /// and `configuration`, as the store's rows hold them; nil unless it
    /// ran. A `--since` run's results are merged with its base's
    /// (`MutationMerge`), the merge's notes added to the run's reason; a
    /// full run that found nothing to test gives empty results over the
    /// scan's files. The warnings are the mapping's.
    static func mutation(
        of run: MutationRun,
        measured: ScanMeasurements,
        targets: [TargetSummary],
        configuration: SwiftStatsConfiguration
    ) -> MappedMutation {
        guard run.status.state == .ran else {
            return MappedMutation(run: run, report: nil, warnings: [])
        }
        let mapper = MutationMapper(
            measured: measured,
            targets: targets,
            excluded: configuration.excluded.map(GlobPattern.init)
        )
        let record = run.results.flatMap { results in
            run.resultsFile.map { file in
                MutationMapper.run(results, ordinal: 0, resultsFile: file, git: run.git, suspects: run.suspects)
            }
        }
        if let base = run.base {
            let merged = MutationMerge(
                base: base,
                mapper: mapper,
                changes: run.changes ?? MutationChanges(selection: [], tree: [:])
            )
            .merged(results: record == nil ? nil : run.results, run: record, suspects: run.suspects)
            let notes = MutationAdapter.reasonNotes(
                exit: MutationExit(state: run.status.state, reason: run.exitReason, resumable: false),
                results: run.results,
                listsNotCovered: merged.report.listsNotCovered,
                merge: merged.notes,
                fixedFiles: run.fixedFiles
            )
            return MappedMutation(run: run.with(reasonNotes: notes), report: merged.report, warnings: mapper.warnings)
        }
        guard let results = run.results else {
            // A full run that ran without a results file found no code
            // SwiftMutator could test (design §1.5): empty results, stored,
            // carried and reported as any others.
            let tree = Dictionary(measured.files.map { ($0.path, $0.sha256) }) { first, _ in first }
            let report = mapper.nothingTested(in: tree, collectedAt: run.startedAt)
            return MappedMutation(run: run, report: MutationRows.normalized(report), warnings: mapper.warnings)
        }
        guard let record else {
            return MappedMutation(run: run, report: nil, warnings: [])
        }
        let report = mapper.report(of: results, run: record, suspects: run.suspects)
        return MappedMutation(run: run, report: MutationRows.normalized(report), warnings: mapper.warnings)
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

//
//  SnapshotScanner+History.swift
//  SwiftStatsCore
//
//  Where a scan's history comes from (PRD §7.13). History is read from the
//  repository, never from the scanned directory, so a scan of an exported
//  revision can still read it; `diff` and `backfill` choose not to, for
//  speed. A scan outside git, or of no commit, has none.
//

import Foundation

extension SnapshotScanner {
    /// `outcome` with history read from `source` attached, and the run.
    static func addHistory(to outcome: ScanOutcome, source: HistorySource) -> (ScanOutcome, HistoryRun) {
        var result = outcome
        guard case let .commit(top, commit, packagePath) = source else {
            if case let .skipped(reason) = source {
                result.report = outcome.report.with(history: nil, status: HistoryCollector.skipped(reason))
            }
            return (result, HistoryRun(gitVersion: nil, milliseconds: 0))
        }
        let options = outcome.configuration.history
        let gitVersion = HistoryCollector.gitVersion(in: top)
        let input = HistoryInput(
            top: top,
            commit: commit,
            packagePath: packagePath,
            targets: outcome.report.targets,
            records: outcome.report.records,
            files: outcome.report.files,
            excluded: outcome.configuration.excluded,
            options: options
        )
        let (collected, milliseconds) = Stopwatch.time { Result { try HistoryCollector.collect(input) } }
        switch collected {
        case .success(let history):
            let status = CollectorStatus(
                name: HistoryCollector.name,
                state: .ran,
                version: gitVersion,
                reason: nil,
                options: options.recorded
            )
            result.report = outcome.report.with(history: history, status: status)

        case .failure(let error):
            let status = CollectorStatus(
                name: HistoryCollector.name,
                state: .failed,
                version: gitVersion,
                reason: String(describing: error),
                options: options.recorded
            )
            result.report = outcome.report.with(history: nil, status: status)
        }
        return (result, HistoryRun(gitVersion: gitVersion, milliseconds: milliseconds))
    }
}

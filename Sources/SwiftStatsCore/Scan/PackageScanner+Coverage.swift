//
//  PackageScanner+Coverage.swift
//  SwiftStatsCore
//
//  The coverage collector's part of a scan (M5). It runs only when the
//  scan asks for it (`scan --coverage`), and starts once the targets are
//  resolved, since it needs only the package's files, so it runs while the
//  package is measured. The tools' skip reason covers a requested run.
//

import Foundation

extension PackageScanner {
    /// The coverage collector's run on the package at `root`, started in
    /// the background; a skip, already finished, when it wasn't
    /// `requested` or the tools are skipped.
    func startCoverage(
        root: URL,
        configuration: SwiftStatsConfiguration,
        requested: Bool
    ) -> BackgroundJob<CoverageRun> {
        guard requested else {
            return BackgroundJob(finished: .skipped(CoverageAdapter.notRequestedReason))
        }
        if let toolSkipReason {
            return BackgroundJob(finished: .skipped(toolSkipReason))
        }
        return CollectorRun.startCoverage(root: root, configuration: configuration, locator: tools)
    }
}

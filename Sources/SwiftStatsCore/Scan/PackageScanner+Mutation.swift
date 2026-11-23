//
//  PackageScanner+Mutation.swift
//  SwiftStatsCore
//
//  The SwiftMutator collector's part of a scan (M6, design §1). It runs
//  only when the scan asks for it (`scan --mutation`), alone, after every
//  other collector has finished, since SwiftMutator times the package's
//  tests and sets each mutant's time limit from them, so nothing else may
//  compete for the CPU. The tools' skip reason covers a requested run.
//

import Foundation

extension PackageScanner {
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

//
//  ScanOutcome.swift
//  SwiftStatsCore
//
//  A scan's report and what a snapshot records beyond it (PRD §6.2): each
//  collector's run time, the binary it ran, and the build identity a run
//  established itself.
//

import Foundation

/// A scan's report with each collector's run time and executable.
struct ScanOutcome {
    /// The scan JSON.
    var report: ScanReport
    /// Wall-clock milliseconds by collector name, `swiftstats` included.
    let milliseconds: [String: Int]
    /// The binary each external collector ran, by name.
    let executables: [String: URL]
    /// The build identity each external collector that established one
    /// itself reported, by name (the coverage collector's `swift:<version>`).
    let identities: [String: String]
    /// The configuration the scan used.
    let configuration: SwiftStatsConfiguration

    /// The outcome of a scan that gave `report` under `configuration`,
    /// measured in `measureMilliseconds`, with the external collectors'
    /// timed runs, the side-effect step and the dependency step.
    init(
        report: ScanReport,
        configuration: SwiftStatsConfiguration,
        measureMilliseconds: Int,
        adapters: [TimedAdapterResult],
        effects: PackageScanner.EffectScan,
        dependencies: PackageScanner.DependencyScan
    ) {
        var times = [
            SwiftStatsCollector.name: measureMilliseconds,
            EffectCollector.name: effects.milliseconds,
            DependencyGraphAdapter.name: dependencies.milliseconds
        ]
        var binaries: [String: URL] = [:]
        var reported: [String: String] = [:]
        for run in adapters {
            times[run.result.status.name] = run.milliseconds
            binaries[run.result.status.name] = run.executable
            reported[run.result.status.name] = run.identity
        }
        binaries[DependencyGraphAdapter.name] = dependencies.executable
        self.report = report
        milliseconds = times
        executables = binaries
        identities = reported
        self.configuration = configuration
    }
}

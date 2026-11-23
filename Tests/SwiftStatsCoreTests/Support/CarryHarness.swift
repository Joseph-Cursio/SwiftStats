import Foundation
@testable import SwiftStatsCore

/// What the coverage carry tests share (M5, design §6): workspaces on a
/// package, a snapshot's coverage run, roll-up coverage numbers as lines,
/// and a check that a rescan is refused without writing anything.
enum CarryHarness {
    /// A workspace on `package`, scanning as `build`.
    static func workspace(_ package: TemporaryPackage, build: SwiftStatsBuild) throws -> SnapshotWorkspace {
        try SnapshotWorkspace(
            packageRoot: package.root,
            configurationFile: nil,
            storeOverride: nil,
            build: build,
            describer: package.describer,
            tools: SnapshotHarness.noTools
        )
    }

    /// The coverage run in `info`.
    static func coverageRun(_ info: SnapshotInfo) -> CollectorRunInfo? {
        info.collectors.first { $0.name == CoverageAdapter.name }
    }

    /// `rollups`' coverage numbers, one line each, sorted.
    static func coverageNumbers(_ rollups: [Rollup]) throws -> [String] {
        try rollups.flatMap { rollup in
            try RollupMetrics.metrics(of: rollup)
                .filter { $0.collector == CoverageAdapter.name }
                .map { "\(rollup.scope.rawValue) \(rollup.name) \($0.path) \($0.value)" }
        }
        .sorted()
    }

    /// The stored rows' coverage numbers, one line each, sorted.
    static func coverageNumbers(_ rows: [RollupMetricRow]) -> [String] {
        rows.filter { $0.collector == CoverageAdapter.name }
            .map { "\($0.scope.rawValue) \($0.name) \($0.metric) \($0.value)" }
            .sorted()
    }

    /// What happens when `workspace` stores `held` and then `rescan`: the
    /// store error the second save throws, if any, and whether `held` kept
    /// its place and its coverage.
    static func refusal(
        in workspace: SnapshotWorkspace,
        held: ScannedSnapshot,
        rescan: ScannedSnapshot
    ) throws -> (error: StoreError?, kept: Bool) {
        let id = try workspace.save(held, drop: []).id
        var error: StoreError?
        do {
            _ = try workspace.save(rescan, drop: [])
        } catch let refused as StoreError {
            error = refused
        }
        let git = held.info.git
        let current = try workspace.store.snapshotID(
            package: held.info.package,
            packagePath: git.packagePath,
            commit: git.commit,
            isDirty: git.isDirty
        )
        let holding = try workspace.store.heldCoverage(id: id) != nil
        return (error, current == id && holding)
    }
}

//
//  MutationSnapshots.swift
//  SwiftStatsCoreTests
//
//  Snapshots with mutation results made to order (M6): a scanned copy of
//  the Coverage fixture holding its recorded SwiftMutator run mapped as a
//  scan maps it, or a snapshot given other results, another SwiftMutator
//  run or another git state, its roll-ups rebuilt as a scan builds them,
//  so the store and diff can be checked without running the collector.
//

@testable import SwiftStatsCore

/// Builds snapshots with chosen mutation results.
enum MutationSnapshots {
    /// The identity of the recorded SwiftMutator build.
    static let identity = "sha256:5138cbf1b810b127accddd8d4973bb2675195797cbae9b734bd09c0ae5a35ba8"

    /// The SwiftMutator run of a plain scan, which skips it.
    static let skipped = CollectorRunInfo(
        name: MutationAdapter.name,
        state: .skipped,
        reason: MutationAdapter.notRequestedReason,
        version: nil,
        identity: nil,
        identityLabel: nil,
        options: [],
        durationMilliseconds: 0
    )

    /// A SwiftMutator run of build `identity` that ran with the map rule.
    static func ran(identity: String) -> CollectorRunInfo {
        CollectorRunInfo(
            name: MutationAdapter.name,
            state: .ran,
            reason: nil,
            version: "0.1.0",
            identity: identity,
            identityLabel: nil,
            options: ["map: " + MutationMapper.rule],
            durationMilliseconds: 0
        )
    }

    /// A copy of the Coverage fixture scanned at `commit`, holding its
    /// recorded full run mapped and passed through the store's rows as a
    /// scan does, and rolled up.
    static func snapshot(commit: String) throws -> ScannedSnapshot {
        let harness = try MappingHarness.coverage()
        defer { harness.remove() }
        let (results, suspects) = try MappingHarness.coverageRun()
        let mutation = MutationRows.normalized(harness.report(results, suspects: suspects))
        return replacing(
            try SnapshotHarness.scan(harness.package, commit: commit),
            git: SnapshotHarness.git(commit: commit),
            mutation: mutation,
            run: ran(identity: identity)
        )
    }

    /// `mutant` with `verdict`, carried or not as `carried` says.
    static func changing(_ mutant: Mutant, verdict: MutationVerdict, carried: Bool) throws -> Mutant {
        var row = MutantRow(mutant, ordinal: 0, snapshotId: 0)
        row.verdict = verdict.rawValue
        row.carried = carried
        return try row.mutant
    }

    /// `report`'s mutants changed by `change`, dropping those it gives
    /// nil for, as `mode` with `base`, its records and counts worked out
    /// again.
    static func changing(
        _ report: MutationReport,
        mode: MutationMode,
        base: MutationSource?,
        change: (Mutant) throws -> Mutant?
    ) rethrows -> MutationReport {
        MutationReport(
            collectedAt: report.collectedAt,
            complete: report.complete,
            listsNotCovered: report.listsNotCovered,
            mode: mode,
            base: base,
            files: report.files,
            runs: report.runs,
            suspectTests: report.suspectTests,
            mutants: try report.mutants.compactMap(change)
        )
    }

    /// `snapshot` at `git`, with `mutation` as its mutation results and
    /// `run` as its SwiftMutator run, and its roll-ups' mutation results
    /// rebuilt from them.
    static func replacing(
        _ snapshot: ScannedSnapshot,
        git: GitState,
        mutation: MutationReport?,
        run: CollectorRunInfo
    ) -> ScannedSnapshot {
        let old = snapshot.report
        let plain = old.rollups.map { $0.with(mutation: nil) }
        let rollups = mutation.map { report in
            MutationRollupBuilder(targets: old.targets, records: old.records, files: old.files, report: report)
                .rollups(plain)
        } ?? plain
        let status = CollectorStatus(
            name: run.name,
            state: run.state,
            version: run.version,
            reason: run.reason,
            options: run.options
        )
        var report = ScanReport(
            schemaVersion: old.schemaVersion,
            tool: old.tool,
            metrics: old.metrics,
            package: old.package,
            configuration: old.configuration,
            targets: old.targets,
            records: old.records,
            types: old.types,
            files: old.files,
            rollups: rollups,
            sitrep: old.sitrep,
            collectors: (old.collectors.filter { $0.name != run.name } + [status]).sorted { $0.name < $1.name },
            findings: old.findings,
            tests: old.tests,
            dependencies: old.dependencies,
            warnings: old.warnings,
            effects: old.effects,
            properties: old.properties,
            clones: old.clones,
            laws: old.laws,
            coverage: old.coverage,
            mutation: mutation
        )
        report.history = old.history
        let info = SnapshotInfo(
            package: snapshot.info.package,
            git: git,
            date: snapshot.info.date,
            toolchain: snapshot.info.toolchain,
            collectors: (snapshot.info.collectors.filter { $0.name != run.name } + [run]).sorted { $0.name < $1.name }
        )
        return ScannedSnapshot(info: info, report: report)
    }
}

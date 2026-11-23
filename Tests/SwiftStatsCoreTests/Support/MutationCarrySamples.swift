//
//  MutationCarrySamples.swift
//  SwiftStatsCoreTests
//
//  The Coverage fixture and its recorded SwiftMutator run as the mutation
//  carry tests use them (M6, design §6.4): scans of a copy of the fixture
//  at a git state and date, some of its files replaced, the same scans
//  holding the recorded run mapped as a scan maps it, the fixture's
//  `Counter.swift` and the edits that move, drop or change its records,
//  and the refusal a rescan of them gets.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// Snapshots of the Coverage fixture with and without mutation results.
enum MutationCarrySamples {
    /// Seconds in a day.
    static let day: TimeInterval = 86_400
    /// How long the hand-made SwiftMutator run took, in milliseconds.
    static let runMilliseconds = 4_321
    /// The reason the hand-made run gave.
    static let original = "2 control runs failed (flaky tests)"
    /// When the recorded run's results were collected.
    static let collectedAt = MappingHarness.coverageStartedAt
    /// The SwiftMutator run the hand-made snapshots hold: ran with flaky
    /// control runs, mapped by this build's rule.
    static let run = CollectorRunInfo(
        name: MutationAdapter.name,
        state: .ran,
        reason: original,
        version: "0.1.0",
        identity: MutationSnapshots.identity,
        identityLabel: "b16642de",
        options: ["coverage: on", "map: " + MutationMapper.rule],
        durationMilliseconds: runMilliseconds
    )
    /// The reason a run carried from the hand-made one gives.
    static let carriedReason = "carried from the scan of \(collectedAt); \(original)"
    /// The hand-made run as a rescan that carries its results records it.
    static let carriedRun = CollectorRunInfo(
        name: MutationAdapter.name,
        state: .ran,
        reason: carriedReason,
        version: run.version,
        identity: run.identity,
        identityLabel: run.identityLabel,
        options: run.options,
        durationMilliseconds: run.durationMilliseconds
    )
    /// A SwiftMutator run whose results were mapped by another rule.
    static let otherRule = CollectorRunInfo(
        name: MutationAdapter.name,
        state: .ran,
        reason: nil,
        version: "0.1.0",
        identity: MutationSnapshots.identity,
        identityLabel: nil,
        options: ["map: an older rule"],
        durationMilliseconds: 0
    )
    /// A clean git state at `c1`.
    static let clean = SnapshotHarness.git(commit: "c1")
    /// The fixture's file whose records the edits move, drop or change.
    static let counterPath = "Sources/Probe/Counter.swift"
    /// The fixture's `Counter.swift`.
    static let counter = (try? String(
        contentsOf: MutationFixture.coverageDirectory.appendingPathComponent(counterPath),
        encoding: .utf8
    )) ?? ""
    /// `Counter.swift` a line lower, so each of its records spans other
    /// lines.
    static let movedCounter = [counterPath: "\n" + counter]
    /// `Counter.swift` with a comment after its last record, so its records
    /// keep their lines and its bytes change.
    static let editedCounter = [counterPath: counter + "// End.\n"]
    /// `Counter.swift` without `neverCalled()`, its last function.
    static let withoutNeverCalled = [
        counterPath: counter.replacingOccurrences(
            of: "\n/// Run by no test.\npublic func neverCalled() -> Int {\n    9\n}\n",
            with: "\n"
        )
    ]

    /// The harness date `days` days later.
    static func later(_ days: TimeInterval) -> Date {
        SnapshotHarness.date + days * day
    }

    /// A git state at `c1` with uncommitted changes hashed as `hash`.
    static func dirty(_ hash: String) -> GitState {
        GitState(commit: "c1", branch: nil, isDirty: true, dirtyHash: hash, packagePath: "")
    }

    /// The fixture scanned at `git` on the harness date as the test build,
    /// without history.
    static func scan(git: GitState) throws -> ScannedSnapshot {
        try scan(git: git, files: [:], date: SnapshotHarness.date)
    }

    /// The fixture with `files` replacing some of its files, scanned at
    /// `git` on the harness date as the test build, without history.
    static func scan(git: GitState, files: [String: String]) throws -> ScannedSnapshot {
        try scan(git: git, files: files, date: SnapshotHarness.date)
    }

    /// The fixture scanned at `git` on `date` as the test build, without
    /// history.
    static func scan(git: GitState, date: Date) throws -> ScannedSnapshot {
        try scan(git: git, files: [:], date: date)
    }

    /// The fixture with `files` replacing some of its files, scanned at
    /// `git` on `date` as the test build, without history.
    static func scan(git: GitState, files: [String: String], date: Date) throws -> ScannedSnapshot {
        let harness = try MappingHarness.coverage()
        defer { harness.remove() }
        for (path, text) in files {
            try text.write(to: harness.package.root.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        return try SnapshotScanner(
            scanner: PackageScanner(describer: harness.package.describer, tools: SnapshotHarness.noTools),
            build: SnapshotHarness.build
        )
        .scan(
            packageAt: harness.package.root,
            configurationFile: StoreLocation.localConfiguration(packageRoot: harness.package.root),
            git: git,
            toolchain: SnapshotHarness.toolchain,
            date: date,
            history: .skipped("test")
        )
    }

    /// The recorded run mapped onto the fixture as a scan maps it, as the
    /// store's rows hold it.
    static func results() throws -> MutationReport {
        let harness = try MappingHarness.coverage()
        defer { harness.remove() }
        let (results, suspects) = try MappingHarness.coverageRun()
        return MutationRows.normalized(harness.report(results, suspects: suspects))
    }

    /// `plain`, a scan of the unchanged fixture, holding the recorded run's
    /// results collected by `run`, its roll-ups rebuilt.
    static func held(_ plain: ScannedSnapshot, run: CollectorRunInfo) throws -> ScannedSnapshot {
        MutationSnapshots.replacing(plain, git: plain.info.git, mutation: try results(), run: run)
    }

    /// `plain`, a scan of the unchanged fixture, holding the recorded run's
    /// results collected by the hand-made run.
    static func held(_ plain: ScannedSnapshot) throws -> ScannedSnapshot {
        try held(plain, run: run)
    }

    /// `plain` as a scan whose SwiftMutator run went as `run` says, without
    /// results.
    static func without(_ plain: ScannedSnapshot, run: CollectorRunInfo) -> ScannedSnapshot {
        MutationSnapshots.replacing(plain, git: plain.info.git, mutation: nil, run: run)
    }

    /// A SwiftMutator run that ended as `state` says, for `reason`.
    static func ended(_ state: CollectorState, reason: String) -> CollectorRunInfo {
        CollectorRunInfo(
            name: MutationAdapter.name,
            state: state,
            reason: reason,
            version: nil,
            identity: nil,
            identityLabel: nil,
            options: [],
            durationMilliseconds: 0
        )
    }

    /// The key of the record named `name` in `snapshot`.
    static func key(_ name: String, in snapshot: ScannedSnapshot) throws -> String {
        try #require(snapshot.report.records.first { $0.name == name }).key
    }

    /// The first, in key order, of the records of `Counter.swift` that hold
    /// a mutant in `snapshot`.
    static func firstCounterRecord(in snapshot: ScannedSnapshot) throws -> String {
        let keys = Set(try #require(snapshot.report.mutation).records.map(\.key))
        return try #require(
            snapshot.report.records.filter { $0.file == counterPath && keys.contains($0.key) }.map(\.key).min()
        )
    }

    /// The SwiftMutator run in `info`.
    static func mutationRun(_ info: SnapshotInfo) -> CollectorRunInfo? {
        info.collectors.first { $0.name == MutationAdapter.name }
    }

    /// `rollups`' mutation numbers, one line each, sorted.
    static func mutationNumbers(_ rollups: [Rollup]) throws -> [String] {
        try rollups.flatMap { rollup in
            try RollupMetrics.metrics(of: rollup)
                .filter { $0.collector == MutationAdapter.name }
                .map { "\(rollup.scope.rawValue) \(rollup.name) \($0.path) \($0.value)" }
        }
        .sorted()
    }

    /// The stored rows' mutation numbers, one line each, sorted.
    static func mutationNumbers(_ rows: [RollupMetricRow]) -> [String] {
        rows.filter { $0.collector == MutationAdapter.name }
            .map { "\($0.scope.rawValue) \($0.name) \($0.metric) \($0.value)" }
            .sorted()
    }

    /// What happens when `workspace` stores `held` and then `rescan`: the
    /// store error the second save throws, if any, and whether `held` kept
    /// its place and its mutation results.
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
        let holding = try workspace.store.heldMutation(id: id) != nil
        return (error, current == id && holding)
    }

    /// The refusal of a rescan of the snapshot of `Probe` at `c1`, whose
    /// mutation results the recorded run collected, for `reason`.
    static func refused(_ reason: String) -> StoreError {
        .mutationNotKept(snapshot: "Probe at c1", collectedAt: collectedAt, reason: reason)
    }
}

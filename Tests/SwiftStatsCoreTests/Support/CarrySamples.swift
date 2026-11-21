import Foundation
@testable import SwiftStatsCore
import Testing

/// The shapes package and its coverage as the coverage carry tests use
/// them (M5, design §6): scans of it at a git state and date, with the
/// coverage a failing run mapped by this build's rule collected, a
/// workspace whose store they go to, and the refusal a rescan of them
/// gets.
enum CarrySamples {
    /// Seconds in a day.
    static let day: TimeInterval = 86_400
    /// How long the hand-made coverage run took, in milliseconds.
    static let runMilliseconds = 1_234
    /// The text of a failing run's reason.
    static let failing = "tests failing (swift test exited 1); "
        + "coverage merged from the test processes' profiles"
    /// The coverage run the hand-made snapshots hold: failing tests, mapped
    /// by this build's rule.
    static let run = CollectorRunInfo(
        name: CoverageAdapter.name,
        state: .ran,
        reason: failing,
        version: "LLVM version 21.0.0",
        identity: "swift:test swift",
        identityLabel: nil,
        options: ["tests: failing", "map: " + CoverageMapper.rule],
        durationMilliseconds: runMilliseconds
    )
    /// A clean git state at `c1`.
    static let clean = SnapshotHarness.git(commit: "c1")
    /// The run a scan whose `swift` can't be found skips coverage with.
    static let notFound = CollectorRunInfo(
        name: CoverageAdapter.name,
        state: .skipped,
        reason: "`swift` not found on PATH; set collectors.coverage.path",
        version: nil,
        identity: nil,
        identityLabel: nil,
        options: [],
        durationMilliseconds: 0
    )
    /// The shapes package's `Kit` file.
    static let kit = CoverageSamples.shapesFiles["Sources/Kit/Kit.swift"] ?? ""
    /// The shapes package's `Lib` file without its internal helper.
    static let withoutHelper = [
        "Sources/Lib/Lib.swift": (CoverageSamples.shapesFiles["Sources/Lib/Lib.swift"] ?? "")
            .replacingOccurrences(of: "func helper() -> Int {\n    1\n}", with: "")
    ]

    /// A git state at `c1` with uncommitted changes hashed as `hash`.
    static func dirty(_ hash: String) -> GitState {
        GitState(commit: "c1", branch: nil, isDirty: true, dirtyHash: hash, packagePath: "")
    }

    /// The shapes package scanned at `git` on the harness date as the test
    /// build, without history.
    static func scan(git: GitState) throws -> ScannedSnapshot {
        try scan(git: git, files: [:], date: SnapshotHarness.date)
    }

    /// The shapes package with `files` replacing some of its files, scanned
    /// at `git` on the harness date as the test build, without history.
    static func scan(git: GitState, files: [String: String]) throws -> ScannedSnapshot {
        try scan(git: git, files: files, date: SnapshotHarness.date)
    }

    /// The shapes package scanned at `git` on `date` as the test build,
    /// without history.
    static func scan(git: GitState, date: Date) throws -> ScannedSnapshot {
        try scan(git: git, files: [:], date: date)
    }

    /// The shapes package with `files` replacing some of its files, scanned
    /// at `git` on `date` as the test build, without history.
    static func scan(git: GitState, files: [String: String], date: Date) throws -> ScannedSnapshot {
        let package = try TemporaryPackage(
            CoverageSamples.shapesFiles.merging(files) { $1 },
            targets: CoverageSamples.shapesTargets
        )
        defer { package.remove() }
        return try SnapshotScanner(
            scanner: PackageScanner(describer: package.describer, tools: SnapshotHarness.noTools),
            build: SnapshotHarness.build
        )
        .scan(
            packageAt: package.root,
            configurationFile: nil,
            git: git,
            toolchain: SnapshotHarness.toolchain,
            date: date,
            history: .skipped("test")
        )
    }

    /// `plain` given the shapes coverage for its records, in the order a
    /// scan gives it, collected by `run`.
    static func covered(_ plain: ScannedSnapshot, run: CollectorRunInfo) throws -> ScannedSnapshot {
        CoverageSnapshots.replacing(
            plain,
            git: plain.info.git,
            coverage: CoverageRows.normalized(try CoverageSamples.shapes(records: plain.report.records)),
            run: run
        )
    }

    /// `plain` given the shapes coverage for its records, collected by the
    /// failing run.
    static func covered(_ plain: ScannedSnapshot) throws -> ScannedSnapshot {
        try covered(plain, run: run)
    }

    /// The key of the record named `name` in `snapshot`.
    static func key(_ name: String, in snapshot: ScannedSnapshot) throws -> String {
        try #require(snapshot.report.records.first { $0.name == name }).key
    }

    /// A new, empty package and a workspace on it, whose store the
    /// hand-made snapshots go to.
    static func store() throws -> (package: TemporaryPackage, workspace: SnapshotWorkspace) {
        let package = try TemporaryPackage([:])
        return (package, try CarryHarness.workspace(package, build: SnapshotHarness.build))
    }

    /// The refusal of a rescan of the snapshot of `Probe` at `c1`, whose
    /// coverage was collected by the hand-made scans, for `reason`.
    static func refused(_ reason: String) -> StoreError {
        .coverageNotKept(
            snapshot: "Probe at c1",
            collectedAt: SnapshotScanner.format(SnapshotHarness.date),
            reason: reason
        )
    }
}

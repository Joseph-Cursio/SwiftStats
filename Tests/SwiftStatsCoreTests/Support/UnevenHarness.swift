//
//  UnevenHarness.swift
//  SwiftStatsCoreTests
//
//  Snapshots for uneven clone testing (M5): a package of four-line
//  functions scanned with a fake SwiftCloneDetector reporting the classes
//  a test sets, given hand-made coverage whose line data a test sets too,
//  stored and read back, so the signal reads what `report` reads.
//

import Foundation
@testable import SwiftStatsCore

/// Stores snapshots with chosen clone classes and line coverage.
enum UnevenHarness {
    /// The file holding the functions.
    static let file = "Sources/Lib/Twins.swift"
    /// The lines one function and the blank line after it take.
    private static let pitch = 5
    /// The lines of a function.
    private static let length = 4

    /// `count` functions `f0`, `f1`, …, function `n` on the four lines
    /// `lines(of: n)`, each followed by a blank line.
    static func functions(_ count: Int) -> String {
        (0..<count).map { index in
            "func f\(index)(_ value: Int) -> Int {\n    let step = value + \(index)\n    return step * 2\n}\n"
        }
        .joined(separator: "\n")
    }

    /// The lines of function `index` of `functions(_:)`.
    static func lines(of index: Int) -> ClosedRange<Int> {
        (index * pitch + 1)...(index * pitch + length)
    }

    /// The key of function `index`.
    static func key(_ index: Int) -> String {
        "Lib::func f\(index)(_: Int) -> Int"
    }

    /// A run of `lines` with `count`.
    static func run(_ lines: ClosedRange<Int>, _ count: Int64) -> CoverageLineRun {
        CoverageLineRun(start: lines.lowerBound, end: lines.upperBound, count: count, partlyRun: false)
    }

    /// `files` as a package scanned with a fake SwiftCloneDetector
    /// reporting `clones`, given coverage whose line data is `runs` by
    /// file, stored in a new store and read back.
    static func stored(
        _ files: [String: String],
        clones: [FakeClone],
        runs: [String: [CoverageLineRun]]
    ) throws -> StoredSnapshot {
        let coverage = CoverageReport(
            records: [],
            attachments: [],
            unmapped: [],
            dropped: CoverageDropped(build: 0, outsideRoot: 0, testFiles: 0, otherPackage: 0),
            bundles: ["LibTests"],
            tests: "passed",
            saturated: [],
            files: runs.keys.sorted().map { CoverageFileLines(file: $0, lines: runs[$0] ?? [], skipped: []) }
        )
        return try stored(files, clones: clones, coverage: coverage)
    }

    /// `files` as a package scanned with a fake SwiftCloneDetector
    /// reporting `clones`, without coverage, as a scan without
    /// `--coverage`, stored in a new store and read back.
    static func stored(_ files: [String: String], clones: [FakeClone]) throws -> StoredSnapshot {
        try stored(files, clones: clones, coverage: nil)
    }

    /// `files` scanned with the fake detector reporting `clones`, given
    /// `coverage` when set, stored and read back.
    private static func stored(
        _ files: [String: String],
        clones: [FakeClone],
        coverage: CoverageReport?
    ) throws -> StoredSnapshot {
        var outputs: [String: String] = [:]
        for run in ["default", "--type3", "--sequence", "--type1"] {
            let reported = run == "--type1" ? clones.filter(\.exact) : clones.filter { $0.run == run }
            outputs[run] = try CloneRepository.json(reported, run: run)
        }
        let tool = try FakeTool.makeCloneDetector(outputs: outputs, errors: [:], statuses: [:])
        defer { CloneHarness.remove(tool) }
        let package = try TemporaryPackage(files)
        defer { package.remove() }
        var snapshot = try SnapshotHarness.scan(
            package,
            commit: "c1",
            build: SnapshotHarness.build,
            tools: CloneHarness.locator(tool)
        )
        if let coverage {
            snapshot = CoverageSnapshots.replacing(
                snapshot,
                git: snapshot.info.git,
                coverage: coverage,
                run: CoverageSnapshots.ran(options: [])
            )
        }
        let directory = try SnapshotHarness.temporaryDirectory("Uneven")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SnapshotStore(at: directory.appendingPathComponent("stats.sqlite"))
        return try store.load(id: try store.save(snapshot))
    }
}

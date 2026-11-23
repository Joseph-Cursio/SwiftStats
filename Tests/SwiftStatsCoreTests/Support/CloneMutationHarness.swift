//
//  CloneMutationHarness.swift
//  SwiftStatsCoreTests
//
//  Snapshots for uneven clone testing's mutation part (M6, design §7.4): a
//  package of four-line functions (`UnevenHarness`'s), scanned with a fake
//  SwiftCloneDetector reporting the classes a test sets, then given
//  hand-made mutation results (mutants with chosen verdicts, places and
//  anchors, and each file's disposition), stored and read back, so the
//  signal reads what `report` reads.
//

import Foundation
@testable import SwiftStatsCore

/// Stores snapshots with chosen clone classes and mutation results.
enum CloneMutationHarness {
    /// What the package holds and what its results say.
    struct Setup {
        /// The package's files, by path.
        var files: [String: String]
        /// The classes the fake detector reports.
        var clones: [FakeClone]
        /// The mutants of the results.
        var mutants: [Mutant] = []
        /// Each Swift file's disposition, by path; tested when absent.
        var dispositions: [String: MutationFileDisposition] = [:]
        /// Whether the results list code no test ran.
        var listsNotCovered = true
        /// Whether the snapshot holds mutation results, rather than being a
        /// scan without `--mutation`.
        var withMutation = true
        /// Whether the fake detector is found; when false the collector is
        /// skipped.
        var withClones = true
    }

    /// The column of a function's first mutant: on `let step = …`'s value.
    static let firstColumn = 16

    /// `count` mutants with `verdict` in function `index` of
    /// `UnevenHarness.functions(_:)`, on its second line, one column apart,
    /// placed on its record.
    static func mutants(_ count: Int, _ verdict: MutationVerdict, function index: Int) -> [Mutant] {
        mutants(count, verdict, function: index, letter: "f", file: UnevenHarness.file)
    }

    /// `count` mutants with `verdict` in function `index` of
    /// `functions(_:letter:)` in `file`, on its second line, one column
    /// apart, placed on its record.
    static func mutants(
        _ count: Int,
        _ verdict: MutationVerdict,
        function index: Int,
        letter: String,
        file: String
    ) -> [Mutant] {
        let line = UnevenHarness.lines(of: index).lowerBound + 1
        return (0..<count).map { offset in
            let point = SourcePosition(line: line, column: firstColumn + offset)
            return MutationSignalHarness.mutant(
                MutationSignalHarness.Planted(verdict: verdict),
                path: file,
                at: point,
                placement: MutationSignalHarness.Placement(
                    place: .record,
                    owner: owner(index, letter: letter),
                    anchor: point
                )
            )
        }
    }

    /// `count` four-line functions named `<letter>0`, `<letter>1`, …, laid
    /// out as `UnevenHarness.functions(_:)` lays out its `f`s.
    static func functions(_ count: Int, letter: String) -> String {
        UnevenHarness.functions(count).replacingOccurrences(of: "func f", with: "func \(letter)")
    }

    /// The record key of function `index` of `functions(_:letter:)`.
    static func owner(_ index: Int, letter: String) -> String {
        "Lib::func \(letter)\(index)(_: Int) -> Int"
    }

    /// The package `setup` describes, scanned with the fake detector,
    /// given its mutation results, stored in a new store and read back.
    static func stored(_ setup: Setup) throws -> StoredSnapshot {
        var outputs: [String: String] = [:]
        for run in ["default", "--type3", "--sequence", "--type1"] {
            let reported = run == "--type1" ? setup.clones.filter(\.exact) : setup.clones.filter { $0.run == run }
            outputs[run] = try CloneRepository.json(reported, run: run)
        }
        let tool = try FakeTool.makeCloneDetector(outputs: outputs, errors: [:], statuses: [:])
        defer { CloneHarness.remove(tool) }
        let package = try TemporaryPackage(setup.files)
        defer { package.remove() }
        var snapshot = try SnapshotHarness.scan(
            package,
            commit: "c1",
            build: SnapshotHarness.build,
            tools: setup.withClones ? CloneHarness.locator(tool) : SnapshotHarness.noTools
        )
        if setup.withMutation {
            snapshot = MutationSnapshots.replacing(
                snapshot,
                git: snapshot.info.git,
                mutation: report(setup),
                run: MutationSnapshots.ran(identity: MutationSnapshots.identity)
            )
        }
        let directory = try SnapshotHarness.temporaryDirectory("CloneMutation")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SnapshotStore(at: directory.appendingPathComponent("stats.sqlite"))
        return try store.load(id: try store.save(snapshot))
    }

    /// The mutation results `setup` gives: its mutants, every Swift file
    /// of the package with its disposition, one run.
    private static func report(_ setup: Setup) -> MutationReport {
        MutationReport(
            collectedAt: "2026-11-21T09:00:00.000Z",
            complete: true,
            listsNotCovered: setup.listsNotCovered,
            mode: .full,
            base: nil,
            files: setup.files.keys.sorted().map { path in
                MutationFile(
                    path: path,
                    sha256: "abc",
                    disposition: setup.dispositions[path] ?? .tested,
                    changedTest: false,
                    run: 0
                )
            },
            runs: [MutationSignalHarness.run(listsNotCovered: setup.listsNotCovered)],
            suspectTests: [],
            mutants: setup.mutants
        )
    }
}

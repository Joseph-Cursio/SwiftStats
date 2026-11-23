import Foundation
@testable import SwiftStatsCore
import Testing

/// The `--since` merge's path rules on their own (M6, design §6.1), with
/// the Mutation fixture's recorded full run as the base, mapped onto a
/// copy of the fixture, and a run that wrote no results file, whose tree
/// is the copy's own hashes: a production path whose hash changed that
/// nothing retested (an ignored file edited) is unresolved and makes the
/// results incomplete, as is one with a base row of no file hash and an
/// unchanged one the base held untested; a case-only rename keeps no old spelling alive and counts the file once;
/// a path spelled in another Unicode form is the same path; and a path the
/// base held unlisted stays so while unchanged.
@Suite("Mutation merge")
struct MutationMergeTests {
    /// The fixture's `main`, as the recordings name it.
    private static let commit = "37124375f4e9e6e1429daf2651e47fc91132142f"

    /// The mapped package, and the base: the recorded full run's results
    /// as the store holds them.
    private static func base() throws -> (MappingHarness, MutationBase) {
        let harness = try MappingHarness.mutation()
        let (results, suspects) = try MappingHarness.fullRun(of: MutationFixture.directory)
        let report = MutationRows.normalized(harness.report(results, suspects: suspects))
        return (harness, MutationBase(revision: "main", commit: commit, report: report, options: []))
    }

    /// The base's tree, by path.
    private static func tree(of base: MutationBase) -> [String: String] {
        Dictionary(uniqueKeysWithValues: base.report.files.compactMap { file in file.sha256.map { (file.path, $0) } })
    }

    /// The merge onto `harness` of a run that wrote no results file over
    /// `tree`, with SwiftMutator's selection `selection`, with `base`.
    private static func merged(
        _ harness: MappingHarness,
        base: MutationBase,
        tree: [String: String],
        selection: [String]
    ) -> MutationMerge.Merged {
        MutationMerge(base: base, mapper: harness.mapper, changes: MutationChanges(selection: selection, tree: tree))
            .merged(results: nil, run: nil, suspects: .unjudged)
    }

    /// The disposition of `path` in `report`'s tree.
    private static func disposition(_ path: String, in report: MutationReport) -> MutationFileDisposition? {
        report.files.first { $0.path == path }?.disposition
    }

    @Test("""
        a production file whose hash changed but that nothing retested is unresolved: its rows are dropped and the \
        results incomplete, as with a base row of no file hash; the others are carried as the base's run
        """)
    func unresolved() throws {
        let (harness, base) = try Self.base()
        defer { harness.remove() }
        var tree = Self.tree(of: base)
        tree["Sources/Extras/Unused.swift"] = String(repeating: "e", count: 64)
        let hashless = try base.report.mutants.map { mutant in
            guard mutant.path == "Sources/Extras/Scale.swift" else {
                return mutant
            }
            var row = MutantRow(mutant, ordinal: 0, snapshotId: 0)
            row.fileSHA256 = nil
            return try row.mutant
        }
        let rowless = MutationBase(
            revision: "main",
            commit: Self.commit,
            report: MappingHarness.rebuilt(base.report, complete: true, files: base.report.files, mutants: hashless),
            options: []
        )

        let merged = Self.merged(harness, base: rowless, tree: tree, selection: [])

        let report = merged.report
        #expect(Self.disposition("Sources/Extras/Unused.swift", in: report) == .unresolved)
        #expect(Self.disposition("Sources/Extras/Scale.swift", in: report) == .unresolved)
        #expect(Self.disposition("Sources/Core/Bounds.swift", in: report) == .carried)
        #expect(report.complete == false)
        #expect(report.mutants.contains { $0.path.hasSuffix("Unused.swift") || $0.path.hasSuffix("Scale.swift") }
            == false)
        #expect(report.mutants.count == base.report.mutants.count - 9)
        #expect(report.mutants.allSatisfy { $0.carried && $0.run == 0 })
        let source = MutationSource(commit: Self.commit, collectedAt: report.collectedAt)
        #expect(report.runs.map(\.carriedFrom) == [source])
        #expect(report.collectedAt == base.report.collectedAt)
        #expect(merged.notes == [
            "merged: 0 files retested since 37124375f4, 5 carried",
            "2 files changed since 37124375f4 have no results"
        ])
    }

    @Test("""
        an unchanged production file the base held untested, as a test target's file then, is unresolved rather \
        than carried: SwiftMutator never tested it, so the results are incomplete
        """)
    func untestedInBase() throws {
        let (harness, base) = try Self.base()
        defer { harness.remove() }
        let moved = "Sources/Core/Bounds.swift"
        let files = base.report.files.map { file in
            guard file.path == moved else {
                return file
            }
            return MutationFile(
                path: file.path,
                sha256: file.sha256,
                disposition: .untested,
                changedTest: false,
                run: nil
            )
        }
        let untested = MutationBase(
            revision: "main",
            commit: Self.commit,
            report: MappingHarness.rebuilt(
                base.report,
                complete: true,
                files: files,
                mutants: base.report.mutants.filter { $0.path != moved }
            ),
            options: []
        )

        let merged = Self.merged(harness, base: untested, tree: Self.tree(of: base), selection: [])

        #expect(base.report.files.first { $0.path == moved }?.disposition == .tested)
        #expect(Self.disposition(moved, in: merged.report) == .unresolved)
        #expect(merged.report.files.first { $0.path == moved }?.run == nil)
        #expect(Self.disposition("Sources/Core/Signs.swift", in: merged.report) == .carried)
        #expect(merged.report.complete == false)
        #expect(merged.notes.last == "1 file changed since 37124375f4 has no results")
    }

    @Test("""
        a case-only rename keeps no old spelling alive: the old path is deleted and the new one, changed with no \
        results file, unlisted, so the file is counted once; a path spelled in another Unicode form is the same \
        path, carried; a path the base held unlisted stays unlisted while unchanged
        """)
    func spellings() throws {
        let (harness, base) = try Self.base()
        defer { harness.remove() }
        var tree = Self.tree(of: base)
        let signs = tree["Sources/Core/Signs.swift"] ?? ""
        tree["Sources/Core/Signs.swift"] = nil
        tree["Sources/Core/signs.swift"] = signs
        let composed = "Sources/Extras/Caf\u{E9}.swift"
        let decomposed = "Sources/Extras/Cafe\u{301}.swift"
        tree[composed] = String(repeating: "c", count: 64)
        let files = base.report.files + [
            MutationFile(path: decomposed, sha256: tree[composed], disposition: .tested, changedTest: false, run: 0),
            MutationFile(
                path: "Sources/Extras/Quiet.swift",
                sha256: String(repeating: "q", count: 64),
                disposition: .unlisted,
                changedTest: false,
                run: nil
            )
        ]
        tree["Sources/Extras/Quiet.swift"] = String(repeating: "q", count: 64)
        let spelled = MutationBase(
            revision: "main",
            commit: Self.commit,
            report: MappingHarness.rebuilt(base.report, complete: true, files: files, mutants: base.report.mutants),
            options: []
        )

        let report = Self.merged(harness, base: spelled, tree: tree, selection: ["Sources/Core/signs.swift"]).report

        #expect(signs.isEmpty == false)
        #expect(Self.disposition("Sources/Core/Signs.swift", in: report) == .deleted)
        #expect(Self.disposition("Sources/Core/signs.swift", in: report) == .unlisted)
        #expect(report.files.count { $0.path.lowercased() == "sources/core/signs.swift" } == 2)
        #expect(report.mutants.contains { $0.path.lowercased() == "sources/core/signs.swift" } == false)
        let cafe = report.files.filter { $0.path == composed }
        #expect(cafe.map(\.disposition) == [.carried])
        #expect(cafe.first?.path.unicodeScalars.elementsEqual(composed.unicodeScalars) == true)
        #expect(Self.disposition("Sources/Extras/Quiet.swift", in: report) == .unlisted)
        #expect(report.complete)
    }

    @Test("SwiftMutator's selection lists a rename and a copy by their new paths and leaves deletions out")
    func changedPaths() {
        let entries = [
            "M", "a.swift", "R087", "old.swift", "new.swift", "D", "gone.swift", "C100", "x.swift", "y.swift"
        ]

        #expect(MutationChanges.changedPaths(entries) == ["a.swift", "new.swift", "y.swift"])
    }
}

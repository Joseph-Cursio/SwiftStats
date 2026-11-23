import Foundation
@testable import SwiftStatsCore
import Testing

/// `scan --mutation --since main` on the Mutation fixture's repository
/// (M6, design §6.1), the fake tools acting out its recorded cases after a
/// full run of `main` was stored as the base: the `since` branch changes
/// `clamp`'s body (later functions in its file shift), renames
/// `Signs.swift` and edits a comment in a test file; `tests-only` edits
/// only the test file, so SwiftMutator writes no results file; and
/// `since-unlisted` edits `neverCalled`, whose file holds no mutant
/// SwiftMutator tests, so it writes none either.
@Suite("Mutation since merge")
struct MutationSinceTests {
    /// The production files the `since` branch leaves alone.
    private static let unchanged = [
        "Sources/Core/Dormant.swift", "Sources/Core/NormalizeA.swift", "Sources/Extras/NormalizeB.swift",
        "Sources/Extras/Scale.swift", "Sources/Extras/Unused.swift"
    ]

    /// `report`'s tree, path by path: disposition, run and whether a
    /// changed test file.
    private static func tree(_ report: MutationReport) -> [String: String] {
        Dictionary(uniqueKeysWithValues: report.files.map { file in
            let run = file.run.map(String.init) ?? "-"
            return (file.path, "\(file.disposition.rawValue) \(run)\(file.changedTest ? " test" : "")")
        })
    }

    /// `report`'s rows in `path`, as compared across a carry: everything
    /// but whether carried and the run.
    private static func rows(_ path: String, of report: MutationReport) -> [String] {
        report.mutants.filter { $0.path == path }.map { mutant in
            [
                "\(mutant.line):\(mutant.column) \(mutant.occurrence) \(mutant.operatorID)",
                mutant.verdict.rawValue, mutant.outcome ?? "-", mutant.killedBy.joined(separator: ","),
                "\(mutant.suspectOnly.map { "\($0)" } ?? "-")", mutant.fileSHA256 ?? "-",
                mutant.anchor.map { "\($0.line):\($0.column)" } ?? "-", mutant.place.rawValue, mutant.owner ?? "-"
            ]
            .joined(separator: " | ")
        }
    }

    /// Each production record of `snapshot` by key: its body hash, its
    /// first line, and its mutants as (operator, line from the record's
    /// first line, column, before, after, verdict), sorted.
    private static func functions(_ snapshot: ScannedSnapshot) -> [String: (String, [String])] {
        let mutation = snapshot.report.mutation
        var functions: [String: (String, [String])] = [:]
        for record in snapshot.report.records where record.role == .production {
            let start = record.range.start.line
            let mutants = (mutation?.mutants ?? []).filter { $0.place == .record && $0.owner == record.key }
                .map { "\($0.operatorID) \($0.line - start):\($0.column) \($0.before) → \($0.after) \($0.verdict)" }
            functions[record.key] = (record.bodyHash, mutants.sorted())
        }
        return functions
    }

    @Test("""
        a --since run asks SwiftMutator for --since and the base's full commit; unchanged files keep the base's \
        rows, carried, placed again on this scan's records and pointing at a copy of the base's run that names \
        the base; changed files are retested whole; a renamed file is retested at its new path and its old path \
        deleted; the changed test file is marked; and the merge is stored as scanned
        """)
    func merged() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        let base = try harness.base()
        let since = try harness.since("since", acting: "since")

        let earlier = try #require(base.snapshot.report.mutation)
        let mutation = try #require(since.snapshot.report.mutation)
        let call = try #require(harness.fake.calls(of: "swift-mutator").last { $0.first == "run" })
        #expect(call.suffix(2) == ["--since", harness.mainCommit])
        #expect(call.contains("--changed-lines") == false)
        #expect(mutation.mode == .since && mutation.complete && mutation.listsNotCovered)
        #expect(mutation.base == MutationSource(commit: harness.mainCommit, collectedAt: earlier.collectedAt))
        #expect(Self.tree(mutation) == [
            "Package.swift": "untested -",
            "Sources/Core/Bounds.swift": "tested 1",
            "Sources/Core/Dormant.swift": "carried 0",
            "Sources/Core/NormalizeA.swift": "carried 0",
            "Sources/Core/Signs.swift": "deleted -",
            "Sources/Core/Signum.swift": "tested 1",
            "Sources/Extras/NormalizeB.swift": "carried 0",
            "Sources/Extras/Scale.swift": "carried 0",
            "Sources/Extras/Unused.swift": "carried 0",
            "Tests/CoreTests/BoundsTests.swift": "untested -",
            "Tests/CoreTests/NormalizeTests.swift": "untested -",
            "Tests/CoreTests/SignTests.swift": "untested - test",
            "Tests/ExtrasTests/ScaleTests.swift": "untested -"
        ])
        for path in Self.unchanged {
            #expect(Self.rows(path, of: mutation) == Self.rows(path, of: earlier))
            #expect(mutation.mutants.filter { $0.path == path }.allSatisfy { $0.carried && $0.run == 0 })
        }
        let fresh = mutation.mutants.filter { $0.carried == false }
        #expect(Set(fresh.map(\.path)) == ["Sources/Core/Bounds.swift", "Sources/Core/Signum.swift"])
        #expect(fresh.allSatisfy { $0.run == 1 } && fresh.count == 29)
        #expect(mutation.mutants.contains { $0.path == "Sources/Core/Signs.swift" } == false)
        let runs = mutation.runs
        #expect(runs.map(\.ordinal) == [0, 1] && runs.map(\.mode) == [.full, .since])
        #expect(runs[0].commit == harness.mainCommit && runs[0].carriedFrom == mutation.base)
        #expect(runs[1].commit == harness.repository.commits["since"] && runs[1].carriedFrom == nil)
        #expect(runs[1].since?.commit == harness.mainCommit && runs[1].since?.mergeBase == harness.mainCommit)
        let status = try #require(since.snapshot.info.collectors.first { $0.name == MutationAdapter.name })
        #expect(status.state == .ran && status.identity == harness.fake.identity)
        #expect(status.reason == "merged: 2 files retested since 37124375f4, 5 carried; 1 test file changed since "
            + "37124375f4, so carried verdicts weren't retested against them")
        #expect(try harness.workspace.store.load(id: since.id).mutation?.report == mutation)
        let production = since.snapshot.report.rollups.first { $0.scope == .project && $0.name == "production" }
        #expect(production?.mutation?.carried == 30)
    }

    @Test("""
        every function whose key and body are unchanged keeps its mutants' operators, places relative to its \
        first line, code and verdicts, in the unchanged files and in the changed one, whose later functions \
        shifted; the changed function has fresh results
        """)
    func functionsKeepTheirVerdicts() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        let base = Self.functions(try harness.base().snapshot)
        let since = Self.functions(try harness.since("since", acting: "since").snapshot)

        let kept = base.filter { key, value in since[key]?.0 == value.0 }
        let changed = base.keys.filter { since[$0] != nil && since[$0]?.0 != base[$0]?.0 }
        #expect(kept.count == base.count - 1)
        #expect(changed == ["Core::func clamp(_: Int, low: Int, high: Int) -> Int"])
        for (key, value) in kept {
            #expect(since[key]?.1 == value.1, "\(key)")
        }
        #expect(kept["Core::func sign(_: Int) -> Int"]?.1.isEmpty == false)
    }

    @Test("""
        when only a test file changed, SwiftMutator writes no results file: every production file is carried \
        under the base's run, the test file is marked, the results keep the base's date, build and settings, \
        and the reason says carried verdicts weren't retested against it
        """)
    func testsOnly() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        let base = try harness.base()
        let since = try harness.since("tests-only", acting: "tests-only")

        let earlier = try #require(base.snapshot.report.mutation)
        let mutation = try #require(since.snapshot.report.mutation)
        #expect(mutation.files.filter { $0.disposition == .carried }.count == 7)
        #expect(mutation.files.filter(\.changedTest).map(\.path) == ["Tests/CoreTests/SignTests.swift"])
        #expect(mutation.mutants.count == earlier.mutants.count && mutation.mutants.allSatisfy(\.carried))
        #expect(mutation.runs.count == 1 && mutation.collectedAt == earlier.collectedAt && mutation.complete)
        let status = try #require(since.snapshot.info.collectors.first { $0.name == MutationAdapter.name })
        let earlierStatus = base.snapshot.info.collectors.first { $0.name == MutationAdapter.name }
        #expect(status.state == .ran && status.identity == earlierStatus?.identity && status.version == "0.1.0")
        #expect(status.options == earlierStatus?.options)
        #expect(status.reason == "merged: 0 files retested since 37124375f4, 7 carried; 1 test file changed since "
            + "37124375f4, so carried verdicts weren't retested against them")
    }

    @Test("""
        when the changed production file holds no mutant SwiftMutator tests, it writes no results file: the file \
        is unlisted, its rows dropped and its functions not listed, the rest carried, and the results stay \
        complete
        """)
    func unlisted() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        _ = try harness.base()
        let since = try harness.since("since-unlisted", acting: "since-unlisted")

        let mutation = try #require(since.snapshot.report.mutation)
        #expect(mutation.files.first { $0.path == "Sources/Core/Dormant.swift" }?.disposition == .unlisted)
        #expect(mutation.mutants.contains { $0.path == "Sources/Core/Dormant.swift" } == false)
        #expect(mutation.complete && mutation.files.count { $0.disposition == .carried } == 6)
        let core = since.snapshot.report.rollups.first { $0.scope == .module && $0.name == "Core" }
        #expect(core?.mutation?.functions.notListed == 1)
        #expect(core?.mutation?.score.percent != nil)
        let status = since.snapshot.info.collectors.first { $0.name == MutationAdapter.name }
        #expect(status?.reason == "merged: 0 files retested since 37124375f4, 6 carried; 1 changed file holds no "
            + "mutant SwiftMutator tests, so its code no test ran isn't listed")
    }

    @Test("the repository the tests build has the commits the recordings name")
    func commits() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }

        #expect(harness.repository.commits == (try MutationFixture.recordedCommits(in: MutationFixture.directory)))
        let since = try MutationFixture.results(of: "since", in: MutationFixture.directory).facts.since
        #expect(since?.commit == harness.mainCommit && since?.mergeBase == harness.mainCommit)
    }
}

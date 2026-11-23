import Foundation
@testable import SwiftStatsCore
import Testing

/// SwiftMutator's recorded runs (M6, design §11) read as SwiftStats reads
/// them: each case's counts pinned (hand-checked against the fixtures'
/// sources), each report joined one to one with its results file, the
/// recordings still matching the fixtures' bytes, and the fixture
/// repository's commits the ones the recordings name.
@Suite("Recorded mutation runs")
struct MutationRecordingTests {
    /// The text of `file` in the Mutation fixture's recorded case `name`.
    private static func text(_ file: String, of name: String) throws -> String {
        try MutationFixture.text(file, of: name, in: MutationFixture.directory)
    }

    /// How many mutants of `results` have each verdict.
    private static func counts(_ results: MutationResults) -> [MutationVerdict: Int] {
        Dictionary(grouping: results.mutants, by: \.verdict).mapValues(\.count)
    }

    /// The paths of `results`' mutants with `verdict`, each once, sorted.
    private static func paths(_ results: MutationResults, _ verdict: MutationVerdict) -> [String] {
        Set(results.mutants.filter { $0.verdict == verdict }.map(\.key.path)).sorted()
    }

    @Test("the Coverage fixture's full run: 31 killed, 2 survived, 10 not covered, complete")
    func coverageFull() throws {
        let results = try MutationFixture.results(of: "full", in: MutationFixture.coverageDirectory)

        #expect(Self.counts(results) == [.killed: 31, .survived: 2, .notCovered: 10])
        #expect(results.mutants.filter { $0.verdict == .survived }.map(\.key.description) == [
            "Sources/Probe/Accessors.swift:6:34 ReplaceReturnValue",
            "Sources/Probe/Nested.swift:18:5 ReplaceBooleanValue"
        ])
        #expect(results.mutants.contains { $0.key.description == "Sources/Probe/Bom.swift:1:33 ReplaceReturnValue" })
        #expect(Self.paths(results, .notCovered) == [
            "Sources/Probe/Accessors.swift", "Sources/Probe/Counter.swift", "Sources/Probe/Nested.swift",
            "Sources/Probe/Overloads.swift", "Sources/Probe/Secrets.swift"
        ])
        #expect(results.complete && results.listsNotCovered && results.sessions == 1)
        #expect(results.facts.mutantsDropped == 2 && results.facts.operators.count == 10)
        #expect(results.facts.executableSHA256 == "5138cbf1b810b127accddd8d4973bb2675195797cbae9b734bd09c0ae5a35ba8")
        #expect(results.mutants.allSatisfy { $0.isCrash == false && $0.activated != .notRan })
    }

    @Test("the Mutation fixture's full run: clamp's 9 mutants survive, normalizedA's crash kills, 21 not covered")
    func mutationFull() throws {
        let results = try MutationFixture.results(of: "full", in: MutationFixture.directory)

        #expect(Self.counts(results) == [.killed: 26, .survived: 9, .notCovered: 21])
        #expect(results.mutants.filter(\.isCrash).map(\.key.description) == [
            "Sources/Core/NormalizeA.swift:8:28 RelationalOperatorReplacement",
            "Sources/Core/NormalizeA.swift:8:71 SwapTernary"
        ])
        #expect(Self.paths(results, .survived) == ["Sources/Core/Bounds.swift"])
        #expect(results.mutants.filter { $0.verdict == .survived }.allSatisfy { (5...11).contains($0.key.line) })
        #expect(Self.paths(results, .notCovered)
            == ["Sources/Core/Dormant.swift", "Sources/Extras/NormalizeB.swift", "Sources/Extras/Unused.swift"])
        let sideEffect = try #require(results.mutants.first { mutant in
            mutant.key.operatorID == "RemoveSideEffects" && mutant.verdict == .killed
        })
        #expect(sideEffect.key.description == "Sources/Core/NormalizeA.swift:9:29 RemoveSideEffects")
        // Both tests fail; the order SwiftMutator names them in varies by run.
        #expect(Set(sideEffect.killedBy) == ["normalizedAScalesToPercentages()", "normalizedAKeepsAZeroTotal()"])
        // A run stopped at its first failed test never has a complete list.
        #expect(sideEffect.endedBy == "stoppedAtFailedTest" && sideEffect.killedByComplete == .incomplete)
        #expect(results.complete && results.listsNotCovered && results.facts.since == nil)
        #expect(results.facts.workers == 4 && results.facts.stopsAtFirstFailure)
    }

    @Test("the since run retests the changed and renamed files and names its base, the fixture's main commit")
    func since() throws {
        let results = try MutationFixture.results(of: "since", in: MutationFixture.directory)
        let commits = try MutationFixture.recordedCommits(in: MutationFixture.directory)

        let since = try #require(results.facts.since)
        #expect(since.commit == commits["main"] && since.mergeBase == commits["main"] && since.ref == commits["main"])
        #expect(since.files.map(\.path)
            == ["Sources/Core/Bounds.swift", "Sources/Core/Signum.swift", "Tests/CoreTests/SignTests.swift"])
        #expect(Set(results.mutants.map(\.key.path)) == ["Sources/Core/Bounds.swift", "Sources/Core/Signum.swift"])
        #expect(Self.counts(results) == [.killed: 18, .survived: 11])
        #expect(results.mutants.filter { $0.key.path.hasSuffix("Bounds.swift") }.map(\.key.line).max() == 19)
        #expect(results.complete && results.listsNotCovered && results.tree["Sources/Core/Signs.swift"] == nil)
    }

    @Test("the interrupted run ends interrupted by SIGTERM, a signal ending it, and the resume completes it")
    func interruptedAndResumed() throws {
        let interrupted = try MutationFixture.results(of: "interrupted", in: MutationFixture.directory)
        let resumed = try MutationFixture.results(of: "resumed", in: MutationFixture.directory)
        let full = try MutationFixture.results(of: "full", in: MutationFixture.directory)

        #expect(try Self.text("status.txt", of: "interrupted") == "run: signal 15\nreport: exit 0\n")
        #expect(interrupted.end?.reason == "interrupted" && interrupted.end?.detail == "SIGTERM")
        #expect(interrupted.complete == false)
        #expect(interrupted.incompleteReason
            == "the results file is incomplete (\(interrupted.tested) of 35 mutants, ended interrupted)")
        #expect(resumed.sessions == 2 && resumed.complete && resumed.tree == interrupted.tree)
        #expect(resumed.mutants.map(\.key) == full.mutants.map(\.key))
        #expect(resumed.mutants.map(\.verdict) == full.mutants.map(\.verdict))
        #expect(Set(resumed.mutants.compactMap(\.session)) == [1, 2])
    }

    @Test("the stopped run holds only its stopped line; the tests-only and unlisted since runs write no file")
    func runsWithoutResults() throws {
        let stopped = try MutationFixture.contents(of: "stopped", in: MutationFixture.directory)

        #expect(stopped == .stopped(MutationStop(
            step: "baseline",
            reason: "failed",
            detail: "baselineTestFailed",
            failedTests: ["alwaysFails()"],
            failedTestCount: 1
        )))
        #expect(try Self.text("status.txt", of: "stopped") == "run: exit 3\nreport: exit 3\n")
        for name in ["tests-only", "since-unlisted"] {
            #expect(try Self.text("status.txt", of: name) == "run: exit 0\n")
            let recorded = MutationFixture.recorded(name, in: MutationFixture.directory)
            for file in ["results.jsonl", "report.json"] {
                #expect(FileManager.default.fileExists(atPath: recorded.appendingPathComponent(file).path) == false)
            }
        }
        #expect(try Self.text("log-tail.txt", of: "tests-only").contains(
            "and the excludes leave out it, so there is nothing to mutate."
        ))
        #expect(try Self.text("log-tail.txt", of: "since-unlisted").contains(
            "and discovery leaves out it: no target compiles it, or the tests don't cover it, "
                + "so there is nothing to mutate."
        ))
    }

    @Test(
        "each recorded report joins its results one to one, keyless placeholders aside",
        arguments: [
            (MutationFixture.coverageDirectory, "full"), (MutationFixture.directory, "full"),
            (MutationFixture.directory, "since"), (MutationFixture.directory, "interrupted"),
            (MutationFixture.directory, "resumed")
        ]
    )
    func reportsJoin(_ fixture: URL, _ name: String) throws {
        let results = try MutationFixture.results(of: name, in: fixture)
        let data = try MutationFixture.data("report.json", of: name, in: fixture)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let files = try #require(object["fileReports"] as? [[String: Any]])
        let applied = files.flatMap { $0["appliedOperators"] as? [[String: Any]] ?? [] }

        let keys = applied.compactMap { $0["key"] as? String }.compactMap(MutantKey.init(spelled:))
        let report = try SuspectReport.decode(data)

        #expect(keys.count == applied.count { $0["key"] != nil })
        #expect(Set(keys).count == keys.count)
        #expect(Set(keys) == Set(results.mutants.filter { $0.verdict != .notCovered }.map(\.key)))
        #expect(report.unreadableKeys == 0 && report.flagged.isEmpty)
    }

    @Test("the Coverage fixture's suspects were checked, so its failed-test kills are judged; Mutation's weren't")
    func recordedJudgements() throws {
        let coverage = try SuspectReport.decode(
            MutationFixture.data("report.json", of: "full", in: MutationFixture.coverageDirectory)
        )
        let mutation = try SuspectReport.decode(
            MutationFixture.data("report.json", of: "full", in: MutationFixture.directory)
        )
        let coverageResults = try MutationFixture.results(of: "full", in: MutationFixture.coverageDirectory)
        let mutationResults = try MutationFixture.results(of: "full", in: MutationFixture.directory)

        #expect(coverage.suspectsChecked && mutation.suspectsChecked == false)
        #expect(coverage.suspectTests.isEmpty && mutation.suspectTests.isEmpty)
        let judged = coverageResults.mutants.map(coverage.judgement(of:))
        #expect(judged.count { $0 == .notSuspectOnly } == 31 && judged.count { $0 == .suspectOnly } == 0)
        #expect(mutationResults.mutants.allSatisfy { mutation.judgement(of: $0) == .unjudged })
    }
}

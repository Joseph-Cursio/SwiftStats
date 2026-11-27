import Foundation
@testable import SwiftStatsCore
import Testing

/// Reading SwiftMutator's results.jsonl (M6, design §2) from hand-written
/// lines: sessions and `projectDelta`, the last line of a key winning,
/// `retired`, newer formats refused, lines that don't read or belong to no
/// readable session skipped and counted, a `stopped`-only file, not-covered
/// mutants and their tree hashes, and completeness.
@Suite("Mutation results file")
struct MutationResultsTests {
    /// The library file the hand-written runs mutate.
    private static let path = "Sources/Lib/Lib.swift"
    /// Its hash in the first tree.
    private static let firstHash = String(repeating: "a", count: 64)
    /// Its hash in the second tree.
    private static let secondHash = String(repeating: "b", count: 64)

    /// A key on `line` of the library file.
    private static func key(line: Int, operatorID: String = "RelationalBoundary") -> MutantKey {
        MutantKey(path: path, operatorID: operatorID, line: line, column: 9, occurrence: 0)
    }

    /// The results `lines` hold; fails the test when they hold none.
    private static func results(_ lines: [String]) throws -> MutationResults {
        guard case .results(let results) = try MutationResultsFile.read(ResultsLines.file(lines)) else {
            throw MutationFailure(description: "no results")
        }
        return results
    }

    /// Why reading `lines` failed, or nil when it didn't.
    private static func failure(_ lines: [String]) -> String? {
        do {
            _ = try MutationResultsFile.read(ResultsLines.file(lines))
            return nil
        } catch {
            return error.description
        }
    }

    @Test("a resumed session rebuilds its tree through projectDelta, and its retired key, tested again, counts again")
    func resumedSession() throws {
        let tree = [Self.path: Self.firstHash, "Sources/Lib/Gone.swift": Self.firstHash]
        let lines = [
            ResultsLines.header(.init(discovered: 2, tree: tree, notCovered: [Self.key(line: 9)])),
            ResultsLines.mutant(.init(line: 3)),
            ResultsLines.mutant(.init(line: 5, outcome: "passed")),
            ResultsLines.end(.init(reason: "interrupted", detail: "SIGTERM")),
            ResultsLines.header(.init(
                session: 2,
                formatVersion: 3,
                discovered: 2,
                delta: .init(base: tree, files: [Self.path: Self.secondHash], removed: ["Sources/Lib/Gone.swift"]),
                notCovered: [Self.key(line: 9)],
                workers: 2
            )),
            ResultsLines.retired(session: 2, keys: [Self.key(line: 3), Self.key(line: 5)]),
            ResultsLines.mutant(.init(line: 5, outcome: "failed", session: 2)),
            ResultsLines.end(.init(session: 2))
        ]

        let results = try Self.results(lines)

        #expect(results.sessions == 2)
        #expect(results.formatVersions == [3, 4])
        #expect(results.tree == [Self.path: Self.secondHash])
        #expect(results.mutants.map(\.key) == [Self.key(line: 5), Self.key(line: 9)])
        #expect(results.mutants.map(\.verdict) == [.killed, .notCovered])
        #expect(results.mutants.map(\.session) == [2, nil])
        #expect(results.mutants.last?.fileSHA256 == Self.secondHash)
        #expect(results.facts.workers == 2 && results.facts.startedAt == "2026-11-21T09:00:01.000Z")
        #expect(results.end
            == MutationResults.End(reason: "finished", detail: nil, endedAt: "2026-11-21T09:01:02.000Z"))
        #expect(results.tested == 1 && results.complete == false)
        #expect(results.incompleteReason == "the results file is incomplete (1 of 2 mutants, ended finished)")
        #expect(results.skippedLines.isEmpty)
    }

    @Test("a projectDelta whose base tree isn't in the file, or that doesn't make the tree it names, doesn't read")
    func unreadableDelta() throws {
        let tree = [Self.path: Self.firstHash]
        let wrongBase = ResultsLines.header(.init(
            session: 2,
            discovered: 1,
            delta: .init(base: ["Other.swift": Self.firstHash], files: [Self.path: Self.secondHash])
        ))
        let wrongTree = ResultsLines.header(.init(
            session: 2,
            discovered: 1,
            delta: .init(base: tree, files: [Self.path: Self.secondHash], claimedTreeSHA256: Self.firstHash)
        ))

        for header in [wrongBase, wrongTree] {
            let results = try Self.results([
                ResultsLines.header(.init(discovered: 1, tree: tree)),
                ResultsLines.mutant(.init(line: 3, outcome: "passed")),
                ResultsLines.end(.init()),
                header,
                ResultsLines.retired(session: 2, keys: [Self.key(line: 3)]),
                ResultsLines.mutant(.init(line: 3, outcome: "failed", session: 2)),
                ResultsLines.end(.init(session: 2))
            ])

            #expect(results.sessions == 1)
            #expect(results.skippedLines == [4, 5, 6, 7])
            #expect(results.mutants.map(\.verdict) == [.survived])
            #expect(results.tree == tree && results.complete)
        }
    }

    @Test("the last line of a key wins, so a rerun replaces the first run's verdict")
    func rerunWins() throws {
        let results = try Self.results([
            ResultsLines.header(.init(discovered: 1)),
            ResultsLines.mutant(.init(outcome: "timeout", endedBy: "timedOut")),
            ResultsLines.mutant(.init(
                outcome: "failed",
                killedBy: ["checks()"],
                failedTestCount: 1,
                rerunBecause: "timeout"
            )),
            ResultsLines.end(.init())
        ])

        let mutant = try #require(results.mutants.first)
        #expect(results.mutants.count == 1)
        #expect(mutant.verdict == .killed && mutant.rerunBecause == "timeout")
        #expect(mutant.killedBy == ["checks()"] && mutant.killedByComplete == .complete)
        #expect(results.complete && results.incompleteReason == nil)
    }

    @Test("a header in a format newer than 4 refuses the file, wherever it is")
    func newerFormat() {
        let reason = "the results file has formatVersion 5; this SwiftStats reads 1 to 4"

        #expect(Self.failure([ResultsLines.header(.init(formatVersion: 5, discovered: 1))]) == reason)
        #expect(Self.failure([
            ResultsLines.header(.init(discovered: 1)),
            ResultsLines.mutant(.init()),
            ResultsLines.end(.init()),
            ResultsLines.header(.init(session: 2, formatVersion: 5, discovered: 1))
        ]) == reason)
        #expect(Self.failure([ResultsLines.header(.init(formatVersion: 1, discovered: 0))]) == nil)
    }

    @Test("lines that don't read, cut off or NUL-padded, or of a session no header started are skipped and counted")
    func skippedLines() throws {
        let cutOff = String(ResultsLines.mutant(.init(line: 4)).prefix(40))
        let padding = String(repeating: "\u{0}", count: 12)
        let unknownOutcome = ResultsLines.mutant(.init(line: 6, outcome: "vanished"))
        let lines = [
            ResultsLines.header(.init(discovered: 1)),
            "",
            ResultsLines.mutant(.init(line: 3)),
            ResultsLines.mutant(.init(line: 7, session: 2)),
            ResultsLines.control(session: 2, outcome: "passed"),
            ResultsLines.end(.init(session: 2)),
            unknownOutcome,
            #"{"kind":"propertyRerun","session":1}"#,
            #"{"kind":"someday","session":9}"#,
            #"{"no":"kind"}"#,
            ResultsLines.end(.init()),
            cutOff,
            padding
        ]

        let results = try Self.results(lines)

        #expect(results.skippedLines == [4, 5, 6, 7, 10, 12, 13])
        #expect(results.mutants.map(\.key) == [Self.key(line: 3)])
        #expect(results.controlRuns == 0 && results.complete)
        #expect(results.skippedLinesWarning
            == "swiftmutator: skipped 7 lines of the results file that didn't read (4, 5, 6, 7, 10, 12, 13)")
        let many = try Self.results([ResultsLines.header(.init(discovered: 0))] + Array(repeating: "{", count: 12))
        #expect(many.skippedLinesWarning
            == "swiftmutator: skipped 12 lines of the results file that didn't read "
            + "(2, 3, 4, 5, 6, 7, 8, 9, 10, 11, …)")
    }

    @Test("a file holding only a stopped line is a run that stopped before its first mutant")
    func stoppedOnly() throws {
        let contents = try MutationResultsFile.read(ResultsLines.file([ResultsLines.stopped(test: "alwaysFails()")]))

        #expect(contents == .stopped(MutationStop(
            step: "baseline",
            reason: "failed",
            detail: "baselineTestFailed",
            failedTests: ["alwaysFails()"],
            failedTestCount: 1
        )))
    }

    @Test("a file with neither a readable header nor a stopped line isn't a results file")
    func noHeader() {
        let reason = "the results file has no header SwiftStats can read, so it holds no results"

        #expect(Self.failure([ResultsLines.mutant(.init()), ResultsLines.end(.init())]) == reason)
        #expect(Self.failure(["not json"]) == reason)
        #expect(Self.failure([]) == reason)
        #expect(Self.failure([#"{"kind":"header","formatVersion":4}"#]) == reason)
    }

    @Test("mutantsNotCovered absent isn't empty: only a header that lists them, or has coverage off, lists them")
    func listsNotCovered() throws {
        let absent = try Self.results([ResultsLines.header(.init(discovered: 0, listsNotCovered: false))])
        let empty = try Self.results([ResultsLines.header(.init(discovered: 0))])
        let coverageOff = try Self.results([
            ResultsLines.header(.init(discovered: 0, listsNotCovered: false, skipCoverage: true))
        ])

        #expect(absent.listsNotCovered == false)
        #expect(empty.listsNotCovered)
        #expect(coverageOff.listsNotCovered && coverageOff.facts.skipCoverage)
    }

    @Test("not-covered entries come from the last header, take its tree's hash, and give way to a tested key")
    func notCovered() throws {
        let tree = [Self.path: Self.firstHash]
        let lines = [
            ResultsLines.header(.init(discovered: 1, tree: tree, notCovered: [Self.key(line: 2)])),
            ResultsLines.end(.init(reason: "aborted", detail: "tooManyBuildErrors")),
            ResultsLines.header(.init(
                session: 2,
                discovered: 1,
                delta: .init(base: tree, files: [:]),
                notCovered: [
                    Self.key(line: 3),
                    Self.key(line: 4),
                    MutantKey(path: "Elsewhere.swift", operatorID: "SwapTernary", line: 1, column: 1, occurrence: 0)
                ]
            )),
            ResultsLines.mutant(.init(line: 3, session: 2))
        ]

        let results = try Self.results(lines)

        #expect(results.mutants.map(\.key.line) == [1, 3, 4])
        #expect(results.mutants.map(\.verdict) == [.notCovered, .killed, .notCovered])
        #expect(results.mutants.map(\.fileSHA256) == [nil, nil, Self.firstHash])
        #expect(results.mutants.map(\.before) == ["1", ">", "1"])
        #expect(results.mutants.map(\.after) == ["0", ">=", "0"])
        let entry = try #require(results.mutants.last)
        #expect(entry.outcome == nil && entry.endedBy == nil && entry.session == nil && entry.activated == .unknown)
        #expect(entry.killedByComplete == .notRecorded && entry.reused == false)
        #expect(entry.before == "1" && entry.after == "0")
        #expect(results.end == nil)
        #expect(results.incompleteReason == "the results file is incomplete (1 of 1 mutants, with no end line)")
    }

    @Test("an aborted run is incomplete, and control runs are counted with those that didn't pass")
    func abortedAndControls() throws {
        let results = try Self.results([
            ResultsLines.header(.init(discovered: 1)),
            ResultsLines.mutant(.init(outcome: "buildError", endedBy: "couldNotRun")),
            ResultsLines.control("passed"),
            ResultsLines.control("failed"),
            ResultsLines.control("timeout"),
            ResultsLines.end(.init(reason: "aborted", detail: "tooManyBuildErrors"))
        ])

        #expect(results.controlRuns == 3 && results.controlFailures == 2)
        #expect(results.end?.detail == "tooManyBuildErrors")
        #expect(results.complete == false)
        #expect(results.incompleteReason == "the results file is incomplete (1 of 1 mutants, ended aborted)")
    }

    @Test("a line keeps its exit status, duration, file hash and reuse, and its list's completeness")
    func keptFields() throws {
        let results = try Self.results([
            ResultsLines.header(.init(discovered: 2)),
            ResultsLines.mutant(.init(
                line: 3,
                killedBy: ["a()", "b()"],
                failedTestCount: 3,
                fileSHA256: Self.firstHash,
                reused: true
            )),
            ResultsLines.mutant(.init(
                line: 4,
                outcome: "failed",
                endedBy: "stoppedAtFailedTest",
                killedBy: ["a()"],
                failedTestCount: 1
            )),
            ResultsLines.end(.init())
        ])

        let incomplete = try #require(results.mutants.first)
        let stopped = try #require(results.mutants.last)
        #expect(incomplete.killedBy == ["a()", "b()"] && incomplete.killedByComplete == .incomplete)
        #expect(incomplete.fileSHA256 == Self.firstHash && incomplete.reused)
        #expect(incomplete.durationSeconds == 0.5 && incomplete.failedTestCount == 3)
        #expect(stopped.killedByComplete == .incomplete && stopped.reused == false && stopped.fileSHA256 == nil)
        #expect(results.sha256.count == 64)
    }
}

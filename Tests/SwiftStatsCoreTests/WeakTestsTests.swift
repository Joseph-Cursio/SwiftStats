import Foundation
@testable import SwiftStatsCore
import Testing

/// Weak tests (PRD §8, M6, design §7.1): production functions with coverage
/// data, at least 3 scored mutants and at least 80% of lines covered,
/// listed when their function score lies below 50% with a mutant that ran
/// and survived or timed out, or when a kill only suspect tests made;
/// scored by survived, timed-out and suspect-only mutants, ordered by
/// score, then function score cross-multiplied; each part of the funnel
/// summing to its whole. Thresholds come from `signals.weak-tests`.
@Suite("Weak tests")
struct WeakTestsTests {
    /// The harness's shorthand.
    private typealias Harness = MutationSignalHarness

    /// A covered function with `killed` kills and `survived` survivors.
    private static func function(killed: Int, survived: Int) -> Harness.Function {
        Harness.covered(Harness.planted(killed, .killed) + Harness.planted(survived, .survived))
    }

    /// A covered function with `killed` kills, `survived` survivors and
    /// `notCovered` not-covered mutants.
    private static func function(killed: Int, survived: Int, notCovered: Int) -> Harness.Function {
        Harness.covered(
            Harness.planted(killed, .killed) + Harness.planted(survived, .survived)
                + Harness.planted(notCovered, .notCovered)
        )
    }

    /// A function with `covered` of 100 lines run, 1 kill and 3 survivors.
    private static func partly(_ covered: Int) -> Harness.Function {
        Harness.Function(
            lines: Harness.lines(covered, of: 100),
            mutants: Harness.planted(1, .killed) + Harness.planted(3, .survived)
        )
    }

    /// The edge cases: 49% and 50% killed, 80% and 79% covered, 2 and 3
    /// scored mutants.
    private static func edges() throws -> StoredSnapshot {
        try Harness.stored([
            function(killed: 49, survived: 51),
            function(killed: 50, survived: 50),
            partly(80),
            partly(79),
            function(killed: 0, survived: 2),
            function(killed: 1, survived: 2)
        ])
    }

    @Test("""
        at the edges, 49% killed is listed and 50% isn't, 80% covered is and 79% isn't, 3 scored mutants are \
        pooled and 2 counted as fewer; the rule states the thresholds and its funnel counts each case
        """)
    func edges() throws {
        let signal = try Harness.signal(.weakTests, of: Self.edges())

        #expect(signal.leftOut == nil)
        #expect(signal.candidates == 5)
        #expect(signal.items.map(\.subject) == [Harness.key(0), Harness.key(2), Harness.key(5)])
        #expect(signal.items.map(\.score) == [51, 3, 2])
        #expect(signal.members == signal.items)
        #expect(signal.rule == WeakTests.rule(thresholds: SignalThresholds()) + "; "
            + "6 production functions = 6 with coverage data + 0 without; 6 = 5 with at least 3 scored mutants + "
            + "1 with fewer + 0 with only build errors + 0 with none + 0 without results (0 unresolved, 0 unlisted); "
            + "5 = 4 at least 80% covered + 1 less; 4 = 3 listed + 0 under 50% only through code no test ran + "
            + "1 not under 50% and with no suspect-only kill; 3 = 3 by score + 0 by suspect-only kills alone; "
            + "suspects judged for 0 of 101 kills by a failing test among the 4 (a run whose kills name tests in "
            + "fewer than 10 files judges only control-run and flaky suspects); " + WeakTests.killingTestLimits)
        #expect(WeakTests.rule(thresholds: SignalThresholds()).hasPrefix(
            "production functions the tests run (at least 80% of lines covered) whose mutants they mostly don't "
                + "kill (function score under 50%"
        ))
        #expect(Harness.unbalanced(signal.rule).isEmpty)
        let first = try #require(signal.items.first)
        #expect(first.file == Harness.libFile && first.line == 1)
        #expect(first.mutation?.functionScore == MutationScore(killed: 49, scored: 100))
        #expect(first.mutation?.survivors.count == 51)
        #expect(first.coverage?.lines == Harness.lines(4, of: 4))
        #expect(first.ratio?.module == "Lib" && first.ratio?.moduleLines == first.ratio?.projectLines)
    }

    @Test("set thresholds change membership and the rule's words: 60% lists 50%, 75% covered lists 79%, 2 mutants")
    func overrides() throws {
        let thresholds = SignalThresholds(limits: ["weak-tests": ["coverage": 75, "score": 60, "mutants": 2]])
        let signal = try Harness.signal(.weakTests, of: Self.edges(), thresholds: thresholds)

        #expect(signal.candidates == 6)
        #expect(signal.items.map(\.subject) == [0, 1, 2, 3, 4, 5].map(Harness.key))
        #expect(signal.rule.hasPrefix(
            "production functions the tests run (at least 75% of lines covered) whose mutants they mostly don't "
                + "kill (function score under 60%"
        ))
        #expect(signal.rule.contains("among functions with at least 2 scored mutants (build errors aside)"))
        #expect(signal.rule.contains("6 = 6 with at least 2 scored mutants + 0 with fewer"))
        #expect(Harness.unbalanced(signal.rule).isEmpty)
    }

    @Test("""
        the share arm needs a mutant that ran and survived or timed out: a function whose unkilled mutants all lie \
        in code no test ran is counted, not listed, and a timeout counts as unchecked
        """)
    func shareArm() throws {
        let snapshot = try Harness.stored([
            Harness.covered(Harness.planted(1, .killed) + Harness.planted(3, .notCovered)),
            Harness.covered(
                Harness.planted(1, .killed) + Harness.planted(1, .noCoverage) + Harness.planted(2, .notCovered)
            ),
            Harness.covered(Harness.planted(1, .killed) + Harness.planted(2, .timedOut))
        ])
        let signal = try Harness.signal(.weakTests, of: snapshot)

        #expect(signal.items.map(\.subject) == [Harness.key(2)])
        #expect(signal.items.first?.score == 2)
        #expect(signal.items.first?.mutation?.survivors.map(\.verdict) == ["timedOut", "timedOut"])
        #expect(signal.rule.contains("3 = 1 listed + 2 under 50% only through code no test ran + 0 not under 50%"))
        #expect(Harness.unbalanced(signal.rule).isEmpty)
    }

    @Test("""
        a kill judged suspect-only lists a well killed function by suspects alone, naming its suspect tests with \
        why and, for reach, in how many of the files with kills each failed; one \
        judged false or not judged doesn't, and the funnel counts the judged kills by a failing test
        """)
    func suspectArm() throws {
        let suspect = Harness.Planted(verdict: .killed, suspectOnly: JSONFlag(true), killedBy: ["flakyTest()"])
        let cleared = Harness.Planted(verdict: .killed, suspectOnly: JSONFlag(false), killedBy: ["exactTest()"])
        let unjudged = Harness.Planted(verdict: .killed, killedBy: ["exactTest()"])
        let crash = Harness.Planted(verdict: .killed, crash: true)
        let snapshot = try Harness.stored(
            [
                Harness.covered([suspect, cleared, cleared]),
                Harness.covered([cleared, cleared, cleared]),
                Harness.covered([unjudged, unjudged, unjudged]),
                Harness.covered([crash, cleared] + Harness.planted(1, .survived)),
                Harness.covered([suspect] + Harness.planted(3, .survived))
            ],
            Harness.Setup(suspects: [
                MutationSuspectTest(
                    name: "flakyTest()",
                    file: "T.swift",
                    run: 0,
                    why: .flaky,
                    files: nil,
                    filesWithKills: nil
                ),
                MutationSuspectTest(
                    name: "flakyTest()",
                    file: "U.swift",
                    run: 0,
                    why: .reach,
                    files: 9,
                    filesWithKills: 10
                )
            ])
        )
        let signal = try Harness.signal(.weakTests, of: snapshot)

        #expect(signal.items.map(\.subject) == [Harness.key(4), Harness.key(0)])
        #expect(signal.items.map(\.score) == [4, 1])
        let byScore = try #require(signal.items.first?.mutation)
        #expect(byScore.counts.suspectOnly == 1 && byScore.counts.judgedKills == 1)
        let bySuspects = try #require(signal.items.last?.mutation)
        #expect(bySuspects.functionScore == MutationScore(killed: 3, scored: 3))
        #expect(bySuspects.suspects == [
            SignalItem.Suspect(name: "flakyTest()", why: "flaky", files: nil, filesWithKills: nil),
            SignalItem.Suspect(name: "flakyTest()", why: "reach", files: 9, filesWithKills: 10)
        ])
        #expect(bySuspects.killingTests == 2 && bySuspects.firstKillingTests == ["exactTest()", "flakyTest()"])
        #expect(signal.rule.contains("5 = 2 listed + 0 under 50% only through code no test ran + 3 not under 50%"))
        #expect(signal.rule.contains("2 = 1 by score + 1 by suspect-only kills alone"))
        #expect(signal.rule.contains("suspects judged for 8 of 11 kills by a failing test among the 5"))
        #expect(Harness.unbalanced(signal.rule).isEmpty)
    }

    @Test("""
        equal scores sort by function score cross-multiplied, lowest first: 1 of 4 before 1 of 3, which ties with \
        2 of 6 and falls back to the subject
        """)
    func shareOrder() throws {
        let snapshot = try Harness.stored([
            Self.function(killed: 1, survived: 2),
            Self.function(killed: 2, survived: 2, notCovered: 2),
            Self.function(killed: 1, survived: 2, notCovered: 1),
            Self.function(killed: 0, survived: 3)
        ])
        let signal = try Harness.signal(.weakTests, of: snapshot)

        #expect(signal.items.map(\.subject) == [3, 2, 0, 1].map(Harness.key))
        #expect(signal.items.map(\.rank) == [1, 2, 3, 4])
        #expect(signal.items.map(\.score) == [3, 2, 2, 2])
    }

    @Test("""
        functions without coverage data, with only build errors, with no mutant, or in unresolved and unlisted \
        files are counted apart in the funnel and never listed
        """)
    func funnelParts() throws {
        let snapshot = try Harness.stored(
            [
                Harness.Function(lines: nil, mutants: Harness.planted(3, .survived)),
                Harness.covered(Harness.planted(3, .buildError)),
                Harness.covered([]),
                Self.function(killed: 0, survived: 3)
            ],
            Harness.Setup(
                other: [Self.function(killed: 0, survived: 3), Self.function(killed: 0, survived: 3)],
                dispositions: [Harness.otherFile: .unlisted]
            )
        )
        let unresolved = try Harness.stored(
            [Self.function(killed: 0, survived: 3)],
            Harness.Setup(dispositions: [Harness.libFile: .unresolved])
        )
        let signal = try Harness.signal(.weakTests, of: snapshot)

        #expect(signal.items.map(\.subject) == [Harness.key(3)])
        #expect(signal.rule.contains(
            "6 production functions = 5 with coverage data + 1 without; 5 = 1 with at least 3 scored mutants + 0 with "
                + "fewer + 1 with only build errors + 1 with none + 2 without results (0 unresolved, 2 unlisted)"
        ))
        #expect(try Harness.signal(.weakTests, of: unresolved).rule.contains(
            "1 = 0 with at least 3 scored mutants + 0 with fewer + 0 with only build errors + 0 with none + 1 without "
                + "results (1 unresolved, 0 unlisted)"
        ))
        #expect(Harness.unbalanced(signal.rule).isEmpty)
    }
}

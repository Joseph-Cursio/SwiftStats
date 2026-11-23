//
//  MarkdownMutationSignalsTests.swift
//  SwiftStatsCoreTests
//
//  M6's signal tables (design §8): weak tests and genuinely under-tested on
//  the Mutation fixture with its recorded coverage and mutation runs, best
//  property-test target on `PropertyTargetHarness`' package, and uneven
//  clone testing's mutation part on the fixture's clone pair, each with
//  the inputs its table shows; and how a cell says why tests are suspect, cuts
//  long lists, and shows what an item lacks.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Markdown mutation signals")
struct MarkdownMutationSignalsTests {
    /// The function the hand-made items are about.
    private static let subject = "Lib::func f(_: Int) -> Int"
    /// Its file.
    private static let file = "Sources/Lib/F.swift"

    /// A function's results: two kills of seven, both suspect-only, five
    /// survivors, seven killing tests and three suspects, one for each
    /// reason.
    private static let mutationJSON = """
        {
          "counts": {"killed": 2, "crashKills": 0, "survived": 5, "noCoverage": 0, "timedOut": 0, "notCovered": 0,
                     "buildErrors": 0, "suspectOnly": 2, "judgedKills": 2},
          "score": {"killed": 2, "scored": 7, "percent": 28.57},
          "functionScore": {"killed": 2, "scored": 7, "percent": 28.57},
          "killingTests": 7,
          "firstKillingTests": ["a()", "b()", "c()", "d()", "e()"],
          "survivors": [
            {"operator": "ChangeArithmeticOperator", "line": 4, "column": 9, "before": "+", "after": "-",
             "verdict": "survived"},
            {"operator": "RelationalBoundary", "line": 5, "column": 9, "before": "<", "after": "<=",
             "verdict": "survived"},
            {"operator": "SwapTernary", "line": 6, "column": 9, "before": "a ? b : c", "after": "a ? c : b",
             "verdict": "timedOut"},
            {"operator": "ReplaceReturnValue", "line": 7, "column": 5, "before": "x", "after": "0",
             "verdict": "survived"},
            {"operator": "ReplaceReturnValue", "line": 8, "column": 5, "before": "y", "after": "0",
             "verdict": "survived"}
          ],
          "suspects": [
            {"name": "wide()", "why": "reach", "files": 9, "filesWithKills": 10},
            {"name": "flaky()", "why": "flaky"},
            {"name": "broken()", "why": "controlRun"}
          ]
        }
        """

    /// A module with no measured lines, in a project with some.
    private static let ratioJSON = """
        {"module": "Lib", "projectLines": {"testLines": 32, "productionLines": 45}}
        """

    /// The table lines a report shows for `signal`.
    private static func table(_ signal: SignalResult) -> [String] {
        MarkdownSignals.render([signal], history: nil).filter { $0.hasPrefix("|") }
    }

    @Test("""
        weak tests shows the function score, lines covered, first survivors, suspect and killing tests and the \
        module's lines; genuinely under-tested the module's lines against the project's
        """)
    func fixture() throws {
        let snapshot = try MutationSignalFixtureTests.stored()
        let weak = try MutationSignalHarness.signal(.weakTests, of: snapshot)
        let under = try MutationSignalHarness.signal(.genuinelyUnderTested, of: snapshot)

        #expect(Self.table(weak) == [
            "| # | Function | Score | Function score | Lines covered | Survivors | Suspect tests | Killing tests "
                + "| Module test / production lines |",
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
            "| 1 | `func clamp(_: Int, low: Int, high: Int) -> Int` (Sources/Core/Bounds.swift:4) | 9 | 0/9 (0%) "
                + "| 9/9 (100%) | RelationalBoundary@5, RelationalOperatorReplacement@5, "
                + "RelationalOperatorReplacement@5 (+6 more) | — | 0 | 29/30 |"
        ])
        #expect(Self.table(under) == [
            "| # | Function | Score | Function score | Lines covered | Module vs project test / production lines |",
            "| --- | --- | --- | --- | --- | --- |",
            "| 1 | `func normalizedB(_: [Int], log: inout[Int]) -> [Int]` (Sources/Extras/NormalizeB.swift:2) | 7 "
                + "| 0/7 (0%) | 0/6 (0%) | 3/15 vs 32/45 |",
            "| 2 | `func unused(_: Int, _: Int) -> Int` (Sources/Extras/Unused.swift:3) | 7 | 0/7 (0%) | 0/6 (0%) "
                + "| 3/15 vs 32/45 |"
        ])
    }

    @Test("""
        best property-test target shows each suggestion's template and tier with its flags, the first unkilled \
        mutants and the partners; top marks the members
        """)
    func propertyTarget() throws {
        let stored = try PropertyTargetHarness.stored(PropertyTargetSamples.setup())
        let signal = try MutationSignalHarness.signal(.bestPropertyTarget, of: stored)

        #expect(Self.table(signal) == [
            "| # | Function | Score | Suggestions | Unkilled | Partners |",
            "| --- | --- | --- | --- | --- | --- |",
            "| 1 | `Money::func encoded(_: Int) -> String` (Sources/Core/Values.swift:2) | 4 | round-trip "
                + "(Likely); round-trip (Possible) | RelationalOperatorReplacement@3, "
                + "RelationalOperatorReplacement@3 | `Money::func decoded(_: String) -> Int`: 2 unkilled |",
            "| 2 | `Money::func decoded(_: String) -> Int` (Sources/Core/Values.swift:6) | 2 | idempotence "
                + "(Possible, verified) | RelationalOperatorReplacement@7, RelationalOperatorReplacement@7 | — |",
            "| 3 | `Money::func doubled(_: Int) -> Int` (Sources/Core/Values.swift:10) | 2 | idempotence (Strong, "
                + "tested (generated)) | RelationalOperatorReplacement@11, RelationalOperatorReplacement@11 | — |",
            "| 4 | `Money::func clamped(_: Int) -> Int` (Sources/Core/Values.swift:18) | 1 | idempotence "
                + "(Advisory, blocked) | RelationalOperatorReplacement@19 | — |"
        ])
        let top = MarkdownSignals.top(signal, limit: 1).components(separatedBy: "\n")
        #expect(top.contains("| # | Function | Score | Suggestions | Unkilled | Partners | Member |"))
        #expect(top.filter { $0.hasPrefix("| 1 | ") }.map { $0.hasSuffix(" | yes |") } == [true])
    }

    @Test("uneven clone testing's mutation part shows each copy's kills, ran unchecked and never ran, and the class")
    func clones() throws {
        let stored = try CloneMutationFixtureTests.stored([CloneMutationFixtureTests.functions])
        let signal = try MutationSignalHarness.signal(.unevenCloneMutation, of: stored)

        #expect(Self.table(signal) == [
            "| # | Least killed copy | Score | Copies killed | Ran unchecked / never ran | Kind | Mass | Folded |",
            "| --- | --- | --- | --- | --- | --- | --- | --- |",
            "| 1 | `func normalizedB(_: [Int], log: inout[Int]) -> [Int]` (Sources/Extras/NormalizeB.swift:2) | 7 "
                + "| `func normalizedA(_: [Int], log: inout[Int]) -> [Int]` (Sources/Core/NormalizeA.swift:6): "
                + "7/7; `func normalizedB(_: [Int], log: inout[Int]) -> [Int]` "
                + "(Sources/Extras/NormalizeB.swift:2): 0/7 | 0 / 0; 0 / 7 | renamed | 60 | — |"
        ])
    }

    @Test("""
        a cell says why each suspect is suspect as the Mutation section does, cuts survivors after three and \
        killing tests after the first, and shows a dash for missing coverage or ratio
        """)
    func cells() throws {
        let mutation = try JSONDecoder().decode(SignalItem.Mutation.self, from: Data(Self.mutationJSON.utf8))
        let ratio = try JSONDecoder().decode(SignalItem.Ratio.self, from: Data(Self.ratioJSON.utf8))
        let item = SignalItem(
            SignalItem.Draft(subject: Self.subject, file: Self.file, line: 3, mutation: mutation),
            rank: 1,
            score: 7,
            member: true
        )
        let under = SignalItem(
            SignalItem.Draft(subject: Self.subject, file: Self.file, line: 3, ratio: ratio),
            rank: 1,
            score: 5,
            member: true
        )

        let weak = Self.table(SignalResult(name: .weakTests, leftOut: nil, rule: "", candidates: 1, items: [item]))
        let low = Self.table(
            SignalResult(name: .genuinelyUnderTested, leftOut: nil, rule: "", candidates: 1, items: [under])
        )

        let suspects: String = "wide() (reach: fails in 9 of 10 files with kills); flaky() (flaky when rerun "
            + "alone); broken() (failed a control run)"
        let expected: String = "| 1 | `func f(_: Int) -> Int` (Sources/Lib/F.swift:3) | 7 | 2/7 (28.57%) | — | "
            + "ChangeArithmeticOperator@4, RelationalBoundary@5, SwapTernary@6 (+2 more) | \(suspects) | 7: a(), … "
            + "| — |"
        #expect(weak.last == expected)
        #expect(low.last == "| 1 | `func f(_: Int) -> Int` (Sources/Lib/F.swift:3) | 5 | — | — | — vs 32/45 |")
    }
}

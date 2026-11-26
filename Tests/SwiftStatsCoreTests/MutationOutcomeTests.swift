import Foundation
@testable import SwiftStatsCore
import Testing

/// A mutant's key and verdict (M6, design "Verdicts" and §2): every raw
/// outcome a results line may record maps to its verdict, crash kills
/// apart; and a key SwiftMutator spells is read from the right, so a path
/// with spaces and colons and a repeat's ` (#k)` give all five parts; a
/// results line's occurrence at `Int.max` spells its repeat in full.
@Suite("Mutation outcomes and keys")
struct MutationOutcomeTests {
    /// A raw outcome, what the line says beside it, and the verdict.
    struct Case: Sendable, CustomTestStringConvertible {
        /// The raw outcome.
        let outcome: String
        /// `activated`, when written.
        let activated: JSONFlag?
        /// `endedBy`.
        let endedBy: String
        /// Whether `leftOutWithOthers` is written.
        let leftOutWithOthers: Bool
        /// The verdict.
        let verdict: MutationVerdict
        /// Whether it is a crash kill.
        let isCrash: Bool

        var testDescription: String {
            "\(outcome), activated \(activated.map { "\($0.value)" } ?? "absent"), \(endedBy) → \(verdict)"
        }
    }

    /// Every raw outcome, with each `activated` a pass may record.
    static let cases = [
        Case(
            outcome: "failed",
            activated: JSONFlag(true),
            endedBy: "stoppedAtFailedTest",
            leftOutWithOthers: false,
            verdict: .killed,
            isCrash: false
        ),
        Case(
            outcome: "runtimeError",
            activated: JSONFlag(true),
            endedBy: "stoppedAtCrash",
            leftOutWithOthers: false,
            verdict: .killed,
            isCrash: true
        ),
        Case(
            outcome: "passed",
            activated: nil,
            endedBy: "exited",
            leftOutWithOthers: false,
            verdict: .survived,
            isCrash: false
        ),
        Case(
            outcome: "passed",
            activated: JSONFlag(true),
            endedBy: "exited",
            leftOutWithOthers: false,
            verdict: .survived,
            isCrash: false
        ),
        Case(
            outcome: "passed",
            activated: JSONFlag(false),
            endedBy: "exited",
            leftOutWithOthers: false,
            verdict: .noCoverage,
            isCrash: false
        ),
        Case(
            outcome: "timeout",
            activated: nil,
            endedBy: "timedOut",
            leftOutWithOthers: false,
            verdict: .timedOut,
            isCrash: false
        ),
        Case(
            outcome: "buildError",
            activated: nil,
            endedBy: "couldNotRun",
            leftOutWithOthers: false,
            verdict: .buildError,
            isCrash: false
        ),
        Case(
            outcome: "buildError",
            activated: nil,
            endedBy: "couldNotRun",
            leftOutWithOthers: true,
            verdict: .buildError,
            isCrash: false
        )
    ]

    @Test("each raw outcome reads as its verdict", arguments: cases)
    func verdicts(_ outcome: Case) throws {
        let lines = [
            ResultsLines.header(.init(discovered: 1)),
            ResultsLines.mutant(.init(
                outcome: outcome.outcome,
                endedBy: outcome.endedBy,
                activated: outcome.activated,
                leftOutWithOthers: outcome.leftOutWithOthers
            )),
            ResultsLines.end(.init())
        ]

        guard case .results(let results) = try MutationResultsFile.read(ResultsLines.file(lines)) else {
            Issue.record("no results")
            return
        }

        let mutant = try #require(results.mutants.first)
        #expect(mutant.verdict == outcome.verdict)
        #expect(mutant.isCrash == outcome.isCrash)
        #expect(mutant.outcome == outcome.outcome)
        #expect(mutant.activated == MutantActivation(outcome.activated))
    }

    @Test("a line that couldn't run, or was left out of the build with others, is a build error whatever it says")
    func buildErrorsWin() {
        let verdict = { (outcome: String, activated: MutantActivation, endedBy: String, leftOut: Bool) in
            MutationVerdict.of(outcome: outcome, activated: activated, endedBy: endedBy, leftOutWithOthers: leftOut)
        }

        #expect(verdict("failed", .ran, "couldNotRun", false) == .buildError)
        #expect(verdict("passed", .ran, "exited", true) == .buildError)
        #expect(verdict("noCoverage", .unknown, "exited", false) == .noCoverage)
        #expect(verdict("vanished", .ran, "exited", false) == nil)
    }

    @Test(
        "a spelled key is read from the right into all five parts",
        arguments: [
            ("Sources/Bar.swift:12:9 SwapTernary", MutantKey(
                path: "Sources/Bar.swift", operatorID: "SwapTernary", line: 12, column: 9, occurrence: 0
            )),
            ("Sources/Bar.swift:12:9 SwapTernary (#2)", MutantKey(
                path: "Sources/Bar.swift", operatorID: "SwapTernary", line: 12, column: 9, occurrence: 1
            )),
            ("My Sources/a:b (#3).swift:7:41 RelationalBoundary (#12)", MutantKey(
                path: "My Sources/a:b (#3).swift", operatorID: "RelationalBoundary", line: 7, column: 41, occurrence: 11
            )),
            ("/abs/x y.swift:1:1 ReplaceReturnValue", MutantKey(
                path: "/abs/x y.swift", operatorID: "ReplaceReturnValue", line: 1, column: 1, occurrence: 0
            ))
        ]
    )
    func spelledKeys(_ spelled: String, _ key: MutantKey) {
        #expect(MutantKey(spelled: spelled) == key)
        #expect(key.description == spelled)
    }

    @Test(
        "a results line's occurrence at the top of what an Int holds spells its repeat in full instead of trapping",
        arguments: [
            (Int.max - 1, " (#9223372036854775807)", true),
            (Int.max, " (#9223372036854775808)", false)
        ]
    )
    func hugeOccurrence(_ occurrence: Int, _ suffix: String, _ readsBack: Bool) throws {
        let lines = [
            ResultsLines.header(.init(discovered: 1)),
            ResultsLines.mutant(.init(occurrence: occurrence)),
            ResultsLines.end(.init())
        ]

        guard case .results(let results) = try MutationResultsFile.read(ResultsLines.file(lines)) else {
            Issue.record("no results")
            return
        }

        let key = try #require(results.mutants.first).key
        #expect(key.occurrence == occurrence)
        #expect(key.description == "Sources/Lib/Lib.swift:3:9 RelationalBoundary" + suffix)
        #expect((MutantKey(spelled: key.description) == key) == readsBack)
    }

    @Test(
        "a spelling that leaves out a part, or has a part that isn't a positive number, is no key",
        arguments: [
            "", "Sources/Bar.swift:12 SwapTernary", "Sources/Bar.swift:12:9", "Sources/Bar.swift:12:9 ",
            "Sources/Bar.swift:0:9 SwapTernary", "Sources/Bar.swift:12:x SwapTernary", ":12:9 SwapTernary",
            "Sources/Bar.swift:12:9 SwapTernary (#1)", "Sources/Bar.swift:12:9 SwapTernary (#x)"
        ]
    )
    func malformedKeys(_ spelled: String) {
        #expect(MutantKey(spelled: spelled) == nil)
    }

    @Test("keys sort by path, line, column, operator and occurrence")
    func keyOrder() {
        let keys = [
            MutantKey(path: "b.swift", operatorID: "A", line: 1, column: 1, occurrence: 0),
            MutantKey(path: "a.swift", operatorID: "B", line: 2, column: 1, occurrence: 0),
            MutantKey(path: "a.swift", operatorID: "A", line: 2, column: 1, occurrence: 1),
            MutantKey(path: "a.swift", operatorID: "A", line: 2, column: 1, occurrence: 0),
            MutantKey(path: "a.swift", operatorID: "Z", line: 1, column: 5, occurrence: 0),
            MutantKey(path: "a.swift", operatorID: "Z", line: 1, column: 4, occurrence: 0)
        ]

        #expect(keys.sorted().map(\.description) == [
            "a.swift:1:4 Z", "a.swift:1:5 Z", "a.swift:2:1 A", "a.swift:2:1 A (#2)", "a.swift:2:1 B", "b.swift:1:1 A"
        ])
    }
}

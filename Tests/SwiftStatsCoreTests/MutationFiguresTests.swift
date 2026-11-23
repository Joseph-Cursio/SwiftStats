import Foundation
@testable import SwiftStatsCore
import Testing

/// What counted mutants come to (M6, design "Verdicts", §4): SwiftMutator's
/// mutation score and the signals' function score, both multiplied before
/// dividing, the unkilled, run-but-unchecked and unrun tallies, the kills
/// whose suspect flag can be judged, and a function's mutation state.
@Suite("Mutation figures")
struct MutationFiguresTests {
    /// A function's counts and file disposition, and the state they give.
    struct StateCase: Sendable, CustomTestStringConvertible {
        /// Its mutants counted; nil when it has none.
        let counts: MutationCounts?
        /// Its file's disposition; nil when the results don't name it.
        let disposition: MutationFileDisposition?
        /// The state expected.
        let state: MutationFunctionState

        /// The case, for the test's report.
        var testDescription: String {
            "\(state) from \(disposition.map(\.rawValue) ?? "no file")"
        }

        /// The case of `counts` in a file of `disposition`, giving `state`.
        init(_ counts: MutationCounts?, _ disposition: MutationFileDisposition?, _ state: MutationFunctionState) {
            self.counts = counts
            self.disposition = disposition
            self.state = state
        }
    }

    /// Counts with only the verdicts given.
    private static func counts(
        killed: Int = 0,
        crashKills: Int = 0,
        survived: Int = 0,
        noCoverage: Int = 0,
        timedOut: Int = 0,
        notCovered: Int = 0,
        buildErrors: Int = 0
    ) -> MutationCounts {
        MutationCounts(
            killed: killed,
            crashKills: crashKills,
            survived: survived,
            noCoverage: noCoverage,
            timedOut: timedOut,
            notCovered: notCovered,
            buildErrors: buildErrors,
            suspectOnly: 0,
            judgedKills: 0
        )
    }

    @Test("""
        the score multiplies before it divides, so 29 of 100 is 29 where dividing first truncates to 28; the \
        percentage keeps two decimal places and the truncated whole percent is SwiftMutator's
        """)
    func multiplyFirst() {
        let killed = 29
        let hundred = MutationScore(killed: killed, scored: 100)
        let fifty = MutationScore(killed: killed, scored: 50)
        let third = MutationScore(killed: 2, scored: 3)

        #expect(Int(Double(killed) / 100 * 100) == 28)
        #expect(hundred.percent == 29 && hundred.truncatedPercent == 29)
        #expect(fifty.percent == 58 && fifty.truncatedPercent == 58)
        #expect(third.percent == 66.67 && third.truncatedPercent == 66)
        #expect(MutationScore(killed: 1, scored: 3).percent == 33.33)
        #expect(MutationScore(killed: 31, scored: 33).percent == 93.94)
        #expect(MutationScore(killed: 31, scored: 33).truncatedPercent == 93)
        #expect(MutationScore(killed: 7, scored: 7).percent == 100)
    }

    @Test("""
        a score of nothing has no percentage rather than 0, a score without its percentage keeps its counts, and \
        the JSON leaves a missing percentage out
        """)
    func nothingScored() throws {
        let empty = MutationScore(killed: 0, scored: 0)
        let dropped = MutationScore(killed: 3, scored: 4).withoutPercent()

        #expect(empty.percent == nil && empty.truncatedPercent == nil)
        #expect(MutationScore(killed: 0, scored: 5).percent == 0)
        #expect(dropped.killed == 3 && dropped.scored == 4 && dropped.percent == nil)
        #expect(dropped.truncatedPercent == 75)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(dropped)) as? [String: Any]
        #expect(object?.keys.sorted() == ["killed", "scored"])
    }

    @Test("""
        the mutation score leaves out build errors and not-covered mutants, the function score counts the \
        not-covered ones as unkilled, and the tallies split the unkilled into run but unchecked and unrun
        """)
    func scoresAndTallies() {
        let figures = MutationFigures(Self.counts(
            killed: 3,
            crashKills: 1,
            survived: 1,
            noCoverage: 1,
            timedOut: 1,
            notCovered: 2,
            buildErrors: 4
        ))

        #expect(figures.score == MutationScore(killed: 3, scored: 6))
        #expect(figures.score.percent == 50)
        #expect(figures.functionScore == MutationScore(killed: 3, scored: 8))
        #expect(figures.functionScore.percent == 37.5)
        #expect(figures.unkilled == 5 && figures.runButUnchecked == 2 && figures.unrun == 3)
        #expect(figures.failedKills == 2)
    }

    @Test("""
        only build errors score nothing either way, while only not-covered mutants have no mutation score but a \
        function score of 0
        """)
    func edges() {
        let buildErrors = MutationFigures(Self.counts(buildErrors: 3))
        let notCovered = MutationFigures(Self.counts(notCovered: 2))

        #expect(buildErrors.score.percent == nil && buildErrors.functionScore.percent == nil)
        #expect(buildErrors.unkilled == 0 && buildErrors.failedKills == 0)
        #expect(notCovered.score.scored == 0 && notCovered.score.percent == nil)
        #expect(notCovered.functionScore == MutationScore(killed: 0, scored: 2))
        #expect(notCovered.functionScore.percent == 0)
        #expect(notCovered.unkilled == 2 && notCovered.unrun == 2 && notCovered.runButUnchecked == 0)
    }

    @Test(
        """
            a function's state is the first that applies: no results, not listed, scored, only not covered, only \
            build errors, no mutant
            """,
        arguments: [
            StateCase(counts(killed: 1), .unresolved, .noResults),
            StateCase(nil, .unresolved, .noResults),
            StateCase(counts(killed: 1), .unlisted, .notListed),
            StateCase(nil, .unlisted, .notListed),
            StateCase(counts(noCoverage: 1, notCovered: 3), .tested, .scored),
            StateCase(counts(timedOut: 1), .tested, .scored),
            StateCase(counts(survived: 1, buildErrors: 2), .carried, .scored),
            StateCase(counts(killed: 2), nil, .scored),
            StateCase(counts(notCovered: 2, buildErrors: 1), .tested, .notCoveredOnly),
            StateCase(counts(buildErrors: 1), .tested, .buildErrorsOnly),
            StateCase(nil, .tested, .noMutant),
            StateCase(nil, nil, .noMutant),
            StateCase(counts(), .tested, .noMutant)
        ]
    )
    func functionStates(_ stateCase: StateCase) {
        #expect(MutationFunctionState(counts: stateCase.counts, disposition: stateCase.disposition) == stateCase.state)
    }

    @Test("a record's counts tell how many kills by a failing test had their suspect flag judged, true or false")
    func judgedKills() throws {
        let harness = try MappingHarness.coverage()
        defer { harness.remove() }
        let (results, suspects) = try MappingHarness.coverageRun()

        let judged = harness.report(results, suspects: suspects)
        let unjudged = harness.report(results)

        #expect(judged.everyMutant.counts.judgedKills == 31)
        #expect(MutationFigures(judged.everyMutant.counts).failedKills == 31)
        #expect(unjudged.everyMutant.counts.judgedKills == 0)
        let anyLarge = try #require(judged.records.first { $0.key == "Probe::func anyLarge(_: [Int]) -> Bool" })
        #expect(anyLarge.counts.judgedKills == 2 && anyLarge.counts.suspectOnly == 0)
    }
}

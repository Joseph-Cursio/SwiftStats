//
//  WeakTests.swift
//  SwiftStatsCore
//
//  Weak tests (PRD §8, M6, design §7.1): production functions the tests
//  run but don't check. The pool is the production functions outside
//  generated files with coverage data, in mutation state scored or only
//  not covered, with at least `signals.weak-tests.mutants` scored mutants
//  (3). One is listed when at least `coverage` (80%) of its lines ran and
//  either its function score lies below `score` (50%) with at least one
//  mutant that ran and survived or timed out, or a kill only suspect tests
//  made (flag judged true). The share arm needs such a mutant because a
//  function whose unkilled mutants all lie in code no test ran is a
//  coverage finding, not tests that run code without checking it; such
//  functions are counted. Items score by survived and timed-out mutants
//  and suspect-only kills, and sort by score, highest first, then function
//  score, lowest first (cross-multiplied), subject, file and line. The
//  module's test-to-code ratio is context only (U8). Results that don't
//  list code no test ran leave such functions unjudged, as the rule says.
//  The signal isn't ranked.
//

/// The weak tests signal.
enum WeakTests {
    /// The limits of a weak tests judgement.
    struct Limits {
        /// Line coverage at least, in percent.
        let coverage: Double
        /// Function score below, in percent.
        let score: Double
        /// Scored mutants at least.
        let mutants: Int

        /// The limits `thresholds` set.
        init(_ thresholds: SignalThresholds) {
            let signal = SignalThresholds.weakTests
            coverage = thresholds.limit(SignalThresholds.coverage, of: signal) ?? 0
            score = thresholds.limit(SignalThresholds.score, of: signal) ?? 0
            mutants = Int(thresholds.limit(SignalThresholds.mutants, of: signal) ?? 0)
        }
    }

    /// What judging the pool's well covered functions counted.
    private struct Tally {
        /// The functions at least `coverage` covered.
        var covered = 0
        /// Of those, the functions listed by the share arm.
        var byScore = 0
        /// Of those, the functions listed by suspect-only kills alone.
        var bySuspects = 0
        /// Of those, the functions below `score` only through code no
        /// test ran, with no suspect-only kill.
        var unrunOnly = 0
        /// Their kills by a failing test whose suspect flag was judged.
        var judged = 0
        /// Their kills by a failing test.
        var failedKills = 0
    }

    /// The limits of the killing tests an item names, as the rule states
    /// them.
    static let killingTestLimits = "killing tests are a lower bound: a kill names at most 20 tests, only the first "
        + "that failed when SwiftMutator stops at the first failure (its SwiftPM default), and a crash kill "
        + "usually none"

    /// What the rule adds when the results don't list code no test ran:
    /// such functions read as having no mutant.
    static let notListedNote = notListedNote(cause: "a SwiftMutator build before 13f96a46")

    /// What the rule adds when `mutation`, results that don't list code
    /// no test ran, says why they don't.
    static func notListedNote(of mutation: MutationReport) -> String {
        notListedNote(cause: mutation.notListedCause)
    }

    /// What the rule adds when the results don't list code no test ran,
    /// because of `cause`.
    private static func notListedNote(cause: String) -> String {
        "the mutation results don't list code no test ran (\(cause)), so functions no test ran aren't judged"
    }

    /// The rule as reports state it with `thresholds`, before the funnel.
    static func rule(thresholds: SignalThresholds) -> String {
        let limits = Limits(thresholds)
        let coverage = MarkdownNumber.exact(limits.coverage)
        let score = MarkdownNumber.exact(limits.score)
        let fewest = MutationPool.scored(limits.mutants)
        return "production functions the tests run (at least \(coverage)% of lines covered) whose mutants they "
            + "mostly don't kill (function score under \(score)%, code no test ran counting as unkilled, with at "
            + "least one mutant that ran and survived or timed out) or with a kill only suspect tests made, among "
            + "functions with at least \(fewest) (build errors aside); scored by surviving and timed-out mutants "
            + "and suspect-only kills; the test-to-code ratio is shown as context only; after adding checks, run "
            + "scan --mutation (a --since run doesn't retest after test-only changes)"
    }

    /// The signal over `snapshot` with `thresholds`; nil when it holds no
    /// mutation results or no coverage.
    static func compute(_ snapshot: StoredSnapshot, thresholds: SignalThresholds) -> SignalComputation? {
        guard let mutation = snapshot.mutation?.report, let coverage = snapshot.coverage?.report else {
            return nil
        }
        let limits = Limits(thresholds)
        let judge = MutationJudge(snapshot, mutation: mutation, coverage: coverage)
        let ratios = ModuleRatios(snapshot, ratio: nil)
        let pool = MutationPool(judge, minimum: limits.mutants)
        var tally = Tally()
        var scored: [SignalScore] = []
        for candidate in pool.candidates where MutationPool.covers(candidate.lines, atLeast: limits.coverage) {
            tally.covered += 1
            tally.judged += candidate.counts.judgedKills
            tally.failedKills += candidate.figures.failedKills
            let below = MutationPool.isBelow(candidate.figures.functionScore, limits.score)
            let scoreArm = below && candidate.figures.runButUnchecked > 0
            let suspectArm = candidate.counts.suspectOnly > 0
            if scoreArm {
                tally.byScore += 1
            } else if suspectArm {
                tally.bySuspects += 1
            } else if below {
                tally.unrunOnly += 1
            }
            if scoreArm || suspectArm {
                scored.append(item(candidate, judge: judge, ratios: ratios))
            }
        }
        let notes = mutation.listsNotCovered ? "" : "; " + notListedNote(of: mutation)
        return SignalComputation(
            rule: rule(thresholds: thresholds) + "; " + funnel(pool, tally: tally, limits: limits) + notes,
            candidates: pool.candidates.count,
            scored: scored
        )
    }

    /// The funnel from the production functions to the listed ones, each
    /// part summing to its whole, with what the suspect arm rests on and
    /// the killing tests' limits.
    private static func funnel(_ pool: MutationPool, tally: Tally, limits: Limits) -> String {
        let coverage = MarkdownNumber.exact(limits.coverage)
        let score = MarkdownNumber.exact(limits.score)
        let pooled = pool.candidates.count
        let listed = tally.byScore + tally.bySuspects
        let notBelow = tally.covered - listed - tally.unrunOnly
        return pool.funnel(minimum: limits.mutants)
            + "; \(pooled) = \(tally.covered) at least \(coverage)% covered + \(pooled - tally.covered) less; "
            + "\(tally.covered) = \(listed) listed + \(tally.unrunOnly) under \(score)% only through code no test "
            + "ran + \(notBelow) not under \(score)% and with no suspect-only kill; \(listed) = \(tally.byScore) by "
            + "score + \(tally.bySuspects) by suspect-only kills alone; suspects judged for \(tally.judged) of "
            + "\(tally.failedKills) kills by a failing test among the \(tally.covered) (a run whose kills name tests "
            + "in fewer than 10 files judges only control-run and flaky suspects); " + killingTestLimits
    }

    /// The item for `candidate`.
    private static func item(
        _ candidate: MutationPool.Candidate,
        judge: MutationJudge,
        ratios: ModuleRatios
    ) -> SignalScore {
        let row = candidate.row
        let draft = SignalItem.Draft(
            subject: row.key,
            file: row.file,
            line: row.startLine,
            coverage: judge.coveragePayload(of: row),
            mutation: judge.payload(of: row, counts: candidate.counts),
            ratio: ratios.payload(row.module)
        )
        let score = Double(candidate.figures.runButUnchecked + candidate.counts.suspectOnly)
        let functionScore = candidate.figures.functionScore
        let order = SignalSortKey([
            .number(-score),
            .fraction(functionScore.killed, of: functionScore.scored),
            .text(row.key),
            .text(row.file),
            .number(Double(row.startLine))
        ])
        return SignalScore(draft, score: score, sortKey: order)
    }
}

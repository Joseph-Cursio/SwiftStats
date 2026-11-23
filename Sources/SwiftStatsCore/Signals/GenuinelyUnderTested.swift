//
//  GenuinelyUnderTested.swift
//  SwiftStatsCore
//
//  Genuinely under-tested (PRD §8, M6, design §7.2): production functions
//  where coverage, mutation and the module's test code agree. The pool is
//  weak tests': production functions outside generated files with coverage
//  data, in mutation state scored or only not covered, with at least
//  `signals.genuinely-under-tested.mutants` scored mutants (3). One is
//  listed when at most `coverage` (20%) of its lines ran, its function
//  score lies below `score` (20%), and its module's test code is low: no
//  test line measured against it, a test-to-code line ratio below the
//  project's (U8), or, when the configuration sets `ratio`, below that
//  (`ModuleRatios`). With one production module whose tests are measured,
//  the module's ratio is the project's, so without `ratio` nothing can be
//  listed, as the funnel says first. Items score by unkilled mutants (U13)
//  and sort by score, highest first, then line coverage, lowest first
//  (cross-multiplied), subject, file and line. The signal isn't ranked.
//

/// The genuinely under-tested signal.
enum GenuinelyUnderTested {
    /// The limits of a genuinely under-tested judgement.
    struct Limits {
        /// Line coverage at most, in percent.
        let coverage: Double
        /// Function score below, in percent.
        let score: Double
        /// Scored mutants at least.
        let mutants: Int
        /// The test-to-code line ratio below which a module's test code is
        /// low; nil when unset.
        let ratio: Double?

        /// The limits `thresholds` set.
        init(_ thresholds: SignalThresholds) {
            let signal = SignalThresholds.genuinelyUnderTested
            coverage = thresholds.limit(SignalThresholds.coverage, of: signal) ?? 0
            score = thresholds.limit(SignalThresholds.score, of: signal) ?? 0
            mutants = Int(thresholds.limit(SignalThresholds.mutants, of: signal) ?? 0)
            ratio = thresholds.limit(SignalThresholds.ratio, of: signal)
        }
    }

    /// Why the signal is left out when the results don't list code no test ran.
    static let notListedReason = "the mutation results don't list code no test ran (a SwiftMutator build before "
        + "13f96a46), so low scores can't be told from missing ones"

    /// The rule as reports state it with `thresholds`, before the funnel.
    static func rule(thresholds: SignalThresholds) -> String {
        let limits = Limits(thresholds)
        let ratio = limits.ratio.map { limit in
            " or below \(MarkdownNumber.exact(limit)) test lines per production line"
        } ?? ""
        return "production functions where coverage, mutation and the module's test code agree: at most "
            + "\(MarkdownNumber.exact(limits.coverage))% of lines covered, function score under "
            + "\(MarkdownNumber.exact(limits.score))% (code no test ran counting as unkilled), at least "
            + "\(MutationPool.scored(limits.mutants)) (build errors aside), in a module with no test code or a "
            + "test-to-code line ratio below the project's\(ratio) (tests count for a module only when their test "
            + "target depends on it directly); scored by unkilled mutants; SwiftMutator makes no mutants in code no "
            + "test ran, only lists them, so for such code the coverage and mutation tests agree by construction "
            + "and the module ratio is the independent one"
    }

    /// The signal over `snapshot` with `thresholds`; nil when it holds no
    /// mutation results or no coverage.
    static func compute(_ snapshot: StoredSnapshot, thresholds: SignalThresholds) -> SignalComputation? {
        guard let mutation = snapshot.mutation?.report, let coverage = snapshot.coverage?.report else {
            return nil
        }
        let limits = Limits(thresholds)
        let judge = MutationJudge(snapshot, mutation: mutation, coverage: coverage)
        let ratios = ModuleRatios(snapshot, ratio: limits.ratio)
        let pool = MutationPool(judge, minimum: limits.mutants)
        let barely = pool.candidates.filter { MutationPool.covers($0.lines, atMost: limits.coverage) }
        var notLow = 0
        var notBelow = 0
        var scored: [SignalScore] = []
        for candidate in barely {
            if MutationPool.isBelow(candidate.figures.functionScore, limits.score) == false {
                notBelow += 1
            } else if ratios.standing(candidate.row.module).isLow {
                scored.append(item(candidate, judge: judge, ratios: ratios))
            } else {
                notLow += 1
            }
        }
        let coverageText = MarkdownNumber.exact(limits.coverage)
        let scoreText = MarkdownNumber.exact(limits.score)
        let funnel = modules(ratios, limits: limits) + "; " + pool.funnel(minimum: limits.mutants)
            + "; \(pool.candidates.count) = \(barely.count) at most \(coverageText)% covered + "
            + "\(pool.candidates.count - barely.count) more; \(barely.count) = \(scored.count) listed + \(notLow) "
            + "under \(scoreText)% in a module whose test code isn't low + \(notBelow) not under \(scoreText)%"
        return SignalComputation(
            rule: rule(thresholds: thresholds) + "; " + funnel,
            candidates: pool.candidates.count,
            scored: scored
        )
    }

    /// The funnel's first part, the production modules by where their
    /// test code stands, each part summing to its whole; with one
    /// production module whose tests are measured and no ratio set, first
    /// that nothing can be listed.
    private static func modules(_ ratios: ModuleRatios, limits: Limits) -> String {
        let standings = ratios.modules.map(ratios.standing)
        let noTests = standings.count { $0 == .noTestCode }
        let belowProject = standings.count { $0 == .belowProject }
        let belowRatio = standings.count { $0 == .belowRatio }
        let low = noTests + belowProject + belowRatio
        let ratioPart = limits.ratio.map { ratio in
            " + \(belowRatio) below \(MarkdownNumber.exact(ratio)) test lines per production line alone"
        } ?? ""
        let total = ratios.modules.count
        let count = total == 1 ? "1 production module" : "\(total) production modules"
        let counted = "\(count) = \(low) with low test code + "
            + "\(standings.count - low) without; \(low) = \(noTests) with no test code + \(belowProject) below the "
            + "project's ratio" + ratioPart
        guard standings == [.notLow], limits.ratio == nil else {
            return counted
        }
        return "one production module: its ratio is the project's, so no function can be listed; " + counted
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
        let score = Double(candidate.figures.unkilled)
        let order = SignalSortKey([
            .number(-score),
            .fraction(candidate.lines.covered, of: candidate.lines.total),
            .text(row.key),
            .text(row.file),
            .number(Double(row.startLine))
        ])
        return SignalScore(draft, score: score, sortKey: order)
    }
}

//
//  MutationPool.swift
//  SwiftStatsCore
//
//  The pool weak tests and genuinely under-tested share (M6, design §7.1,
//  §7.2), and the start of their funnels: the production functions outside
//  generated files, those with coverage data, and of these the functions
//  in state scored or only not covered with at least the signal's fewest
//  scored mutants (the function score's denominator, build errors aside),
//  the rest counted by why they are out. Shares are compared with their
//  limits exactly, on integers: `killed × 100 < limit × scored`.
//

/// The production functions a per-function mutation signal judges.
struct MutationPool {
    /// A function in the pool.
    struct Candidate {
        /// Its row.
        let row: FunctionRow
        /// Its mutants counted.
        let counts: MutationCounts
        /// What they come to.
        let figures: MutationFigures
        /// Its line coverage.
        let lines: CoverageTally
    }

    /// Percentages are out of this.
    private static let wholePercent = 100.0

    /// The functions in the pool, in the snapshot's order.
    let candidates: [Candidate]
    /// The production functions outside generated files.
    let functions: Int
    /// Those with coverage data.
    let withData: Int
    /// Of those, the functions scored or only not covered with fewer scored
    /// mutants than the fewest.
    let fewer: Int
    /// Of those, the functions with only build errors.
    let buildErrorsOnly: Int
    /// Of those, the functions with no mutant.
    let noMutant: Int
    /// Of those, the functions without results: their file unresolved.
    let unresolved: Int
    /// Of those, the functions without results: their file unlisted.
    let unlisted: Int

    /// The pool of `judge`'s functions with at least `minimum` scored
    /// mutants.
    init(_ judge: MutationJudge, minimum: Int) {
        var pooled: [Candidate] = []
        var dataCount = 0
        var fewerCount = 0
        var buildErrorCount = 0
        var noMutantCount = 0
        var unresolvedCount = 0
        var unlistedCount = 0
        for row in judge.functions.rows {
            guard let lines = judge.lines(of: row) else {
                continue
            }
            dataCount += 1
            switch judge.state(of: row) {
            case .scored, .notCoveredOnly:
                // Both states come from counts, so every such row has them.
                guard let counts = judge.counts(of: row) else {
                    noMutantCount += 1
                    continue
                }
                let figures = MutationFigures(counts)
                if figures.functionScore.scored >= minimum {
                    pooled.append(Candidate(row: row, counts: counts, figures: figures, lines: lines))
                } else {
                    fewerCount += 1
                }

            case .buildErrorsOnly:
                buildErrorCount += 1

            case .noMutant:
                noMutantCount += 1

            case .noResults:
                unresolvedCount += 1

            case .notListed:
                unlistedCount += 1
            }
        }
        candidates = pooled
        withData = dataCount
        fewer = fewerCount
        buildErrorsOnly = buildErrorCount
        noMutant = noMutantCount
        unresolved = unresolvedCount
        unlisted = unlistedCount
        functions = judge.functions.rows.count
    }

    /// Whether `score` lies below `percent`, exactly.
    static func isBelow(_ score: MutationScore, _ percent: Double) -> Bool {
        Double(score.killed) * wholePercent < percent * Double(score.scored)
    }

    /// Whether `lines` covers at least `percent` of its lines, exactly.
    static func covers(_ lines: CoverageTally, atLeast percent: Double) -> Bool {
        Double(lines.covered) * wholePercent >= percent * Double(lines.total)
    }

    /// Whether `lines` covers at most `percent` of its lines, exactly.
    static func covers(_ lines: CoverageTally, atMost percent: Double) -> Bool {
        Double(lines.covered) * wholePercent <= percent * Double(lines.total)
    }

    /// `count` scored mutants, in words.
    static func scored(_ count: Int) -> String {
        count == 1 ? "1 scored mutant" : "\(count) scored mutants"
    }

    /// The funnel down to the pool, `minimum` being the fewest scored
    /// mutants: each part named, its parts summing to it.
    func funnel(minimum: Int) -> String {
        let fewest = Self.scored(minimum)
        let withoutResults = unresolved + unlisted
        return "\(functions) production functions = \(withData) with coverage data + \(functions - withData) "
            + "without; \(withData) = \(candidates.count) with at least \(fewest) + \(fewer) with fewer + "
            + "\(buildErrorsOnly) with only build errors + \(noMutant) with none + \(withoutResults) without "
            + "results (\(unresolved) unresolved, \(unlisted) unlisted)"
    }
}

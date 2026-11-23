//
//  BestPropertyTarget.swift
//  SwiftStatsCore
//
//  Best property-test target (PRD §8, M6, design §7.3, U11): production
//  functions where a property test may pay off most. The suggestions it
//  reads are SwiftInferProperties' algebraic ones located in production
//  code and attached to a production function outside generated files,
//  of any tier (blocked Advisory rows flagged by their `blocked` mark),
//  neither disproven nor rejected; a function already linked to a property
//  test stays in, flagged by its suggestion's `testedBy`, since that
//  property doesn't kill these mutants. The pool is the functions carrying
//  one, in mutation state scored or only not covered. One is listed when
//  at least one of its own mutants isn't killed (survived, timed out, no
//  coverage or not covered), one item per function. Items score by those
//  mutants plus, for each two-function suggestion whose partner resolves
//  to a production record, that partner's unkilled mutants, each partner
//  counted once per item; a partner with its own item is counted there
//  too, and the funnel counts the mutants more than one item counts.
//  Items sort by score, highest first, then their best suggestion's score
//  with Verified's bonus, highest first, subject, file and line. The
//  signal isn't ranked.
//

/// The best property-test target signal.
enum BestPropertyTarget {
    /// What judging the functions with suggestions counted.
    private struct Tally {
        /// The suggestions in the pool's reach.
        var suggestions = 0
        /// The functions carrying them.
        var functions = 0
        /// Those in state scored or only not covered: the pool.
        var withResults = 0
        /// Those with only build errors.
        var buildErrorsOnly = 0
        /// Those with no mutant.
        var noMutant = 0
        /// Those without results: their file unresolved.
        var unresolved = 0
        /// Those without results: their file unlisted.
        var unlisted = 0
        /// Of the pool, the functions every one of whose mutants is killed.
        var allKilled = 0
        /// The partners the listed items add.
        var partners = 0
    }

    /// A listed function before the overlap between items is counted.
    private struct Listed {
        /// Its item.
        let score: SignalScore
        /// The records whose unkilled mutants it counts: its own, then its
        /// partners'.
        let counted: [String]
    }

    /// The rule as reports state it, before the funnel.
    static let rule = "production functions with an algebraic SwiftInferProperties suggestion (any tier, neither "
        + "disproven nor rejected; blocked Advisory rows flagged) and mutants the tests don't kill (survived, timed "
        + "out, no coverage, or not covered), plus a two-function law's partner's; scored by those mutants; after "
        + "writing the property test, run scan --mutation, or SwiftMutator on the file (swift-mutator run "
        + "--files-to-mutate <file>), and read the former survivors' killedBy (a --since run retests nothing when "
        + "only tests changed)"

    /// The signal over `snapshot`; nil when it holds no mutation results.
    static func compute(_ snapshot: StoredSnapshot) -> SignalComputation? {
        guard let mutation = snapshot.mutation?.report else {
            return nil
        }
        let judge = MutationJudge(snapshot, mutation: mutation, coverage: snapshot.coverage?.report)
        let functions = judge.functions
        let suggestions = snapshot.candidates.filter { isPooled($0, functions: functions) }
        let byOwner = Dictionary(grouping: suggestions) { functions.row(of: $0)?.key ?? "" }
        var tally = Tally(suggestions: suggestions.count)
        var listed: [Listed] = []
        for row in functions.rows {
            guard let held = byOwner[row.key] else {
                continue
            }
            tally.functions += 1
            guard let counts = judged(row, judge: judge, tally: &tally) else {
                continue
            }
            guard MutationFigures(counts).unkilled > 0 else {
                tally.allKilled += 1
                continue
            }
            let item = item(row, counts: counts, suggestions: held, judge: judge)
            tally.partners += item.counted.count - 1
            listed.append(item)
        }
        let notes = mutation.listsNotCovered ? "" : "; " + WeakTests.notListedNote(of: mutation)
        return SignalComputation(
            rule: rule + "; " + funnel(tally, listed: listed, judge: judge) + notes,
            candidates: tally.withResults,
            scored: listed.map(\.score)
        )
    }

    /// Whether `candidate` is a suggestion the signal reads: algebraic,
    /// located in production code, attached to one of `functions`, neither
    /// disproven nor rejected.
    private static func isPooled(_ candidate: PropertyCandidate, functions: ProductionFunctions) -> Bool {
        candidate.population == .algebraic && candidate.site == .production && functions.row(of: candidate) != nil
            && candidate.verification?.judgement?.disproven != true && candidate.decision != .rejected
    }

    /// `row`'s mutants counted when it is in the pool (state scored or only
    /// not covered); nil, with why counted in `tally`, when it isn't.
    private static func judged(_ row: FunctionRow, judge: MutationJudge, tally: inout Tally) -> MutationCounts? {
        switch judge.state(of: row) {
        case .scored, .notCoveredOnly:
            // Both states come from counts, so every such row has them.
            guard let counts = judge.counts(of: row) else {
                tally.noMutant += 1
                return nil
            }
            tally.withResults += 1
            return counts

        case .buildErrorsOnly:
            tally.buildErrorsOnly += 1

        case .noMutant:
            tally.noMutant += 1

        case .noResults:
            tally.unresolved += 1

        case .notListed:
            tally.unlisted += 1
        }
        return nil
    }

    /// A suggestion's score with Verified's bonus, as untested property
    /// scores it.
    private static func weight(_ candidate: PropertyCandidate) -> Int {
        candidate.score + (candidate.verification?.judgement?.verified == true ? UntestedProperty.verifiedBonus : 0)
    }

    /// The item for `row`, whose mutants `counts` count, carrying
    /// `suggestions`.
    private static func item(
        _ row: FunctionRow,
        counts: MutationCounts,
        suggestions: [PropertyCandidate],
        judge: MutationJudge
    ) -> Listed {
        let partnerKeys = Set(suggestions.compactMap(\.partnerKey))
            .filter { $0 != row.key && judge.functions.row(key: $0) != nil }
            .sorted()
        let partners = partnerKeys.map { key in
            SignalItem.Partner(key: key, counts: judge.counts(key: key), unkilled: judge.unkilled(key: key))
        }
        let ranked = suggestions.enumerated().sorted { left, right in
            let (leftWeight, rightWeight) = (weight(left.element), weight(right.element))
            if leftWeight != rightWeight {
                return leftWeight > rightWeight
            }
            return (left.element.identity, left.offset) < (right.element.identity, right.offset)
        }
        let best = ranked.map(\.element)
        let draft = SignalItem.Draft(
            subject: row.key,
            file: row.file,
            line: row.startLine,
            mutation: judge.payload(of: row, counts: counts),
            propertyTarget: SignalItem.PropertyTarget(
                suggestions: best.map(SignalItem.Property.init),
                unkilled: judge.unkilled(key: row.key),
                partners: partners
            )
        )
        let score = Double(MutationFigures(counts).unkilled + partners.reduce(0) { $0 + $1.unkilled.count })
        let order = SignalSortKey([
            .number(-score),
            .number(-Double(best.first.map(weight) ?? 0)),
            .text(row.key),
            .text(row.file),
            .number(Double(row.startLine))
        ])
        return Listed(score: SignalScore(draft, score: score, sortKey: order), counted: [row.key] + partnerKeys)
    }

    /// The funnel from the functions carrying suggestions to the listed
    /// ones, each part summing to its whole, with the partners the items
    /// add and the unkilled mutants more than one item counts.
    private static func funnel(_ tally: Tally, listed: [Listed], judge: MutationJudge) -> String {
        let counting = Dictionary(listed.flatMap(\.counted).map { ($0, 1) }, uniquingKeysWith: +)
        let shared = counting.filter { $0.value > 1 }.keys.reduce(0) { total, key in
            total + judge.unkilled(key: key).count
        }
        let withoutResults = tally.unresolved + tally.unlisted
        return "\(counted(tally.functions, "production function")) holding "
            + "\(counted(tally.suggestions, "suggestion")) = \(tally.withResults) with mutation results + "
            + "\(tally.buildErrorsOnly) with only build errors + \(tally.noMutant) with none + \(withoutResults) "
            + "without results (\(tally.unresolved) unresolved, \(tally.unlisted) unlisted); \(tally.withResults) = "
            + "\(listed.count) listed + \(tally.allKilled) with every mutant killed; "
            + "\(counted(tally.partners, "partner")) added, \(counted(shared, "mutant")) counted by more than one item"
    }

    /// `count` and `noun`, plural unless `count` is 1.
    private static func counted(_ count: Int, _ noun: String) -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }
}

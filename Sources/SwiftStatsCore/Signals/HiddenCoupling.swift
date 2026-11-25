//
//  HiddenCoupling.swift
//  SwiftStatsCore
//
//  Hidden coupling (PRD §8, M7, design §8.1, D14): pairs of production
//  families that change together often, by the history window's commits,
//  with no static dependency between them, by the T1 build's index. The
//  pool is the snapshot's coupling pairs, as history names them (families
//  by key), each classed by the first that applies: a family not among
//  the snapshot's records (U), a family with a member in a generated file
//  (G), a family whose root isn't production code (T); the rest have both
//  families in production code (P). Of those, a pair with a family no
//  member of which has a primary USR (W) can't be judged; the judged ones
//  (K) are counted out by the first static dependency that holds: a
//  family reference naming the other's record directly, either way (R);
//  one through a protocol requirement the other's record witnesses,
//  either way (Q); the roots' owning types (`CouplingOwners`) the same,
//  or one nested in the other (Y); a family's reference to the other
//  root's owning type or its members (X). Same file and same module
//  aren't dependencies. A pair with none (C) is listed when its support
//  and confidence reach the limits (L), else counted below them (B),
//  confidence compared exactly with the limit as written (`PercentLimit`). Items score by support and
//  sort by it, then confidence, both highest first, then subject, file
//  and line, then partner and partner file; the subject is the pair's
//  first family, at its root's line, and the payload names its partner.
//  The signal isn't ranked.
//

/// The hidden coupling signal.
enum HiddenCoupling {
    /// What the signal decides of a coupling pair: its funnel term.
    enum Verdict: CaseIterable, Hashable {
        /// No static dependency, below the limits (B).
        case belowLimits
        /// A family with a member in a generated file (G).
        case generated
        /// No static dependency, and the limits reached: listed (L).
        case listed
        /// A family whose root isn't production code (T).
        case nonProduction
        /// One family references the other's record directly (R).
        case references
        /// One family calls through a protocol requirement a record of
        /// the other witnesses (Q).
        case requirement
        /// The roots' owning types are the same, or one nested in the
        /// other (Y).
        case sharedType
        /// One family references the other root's owning type or its
        /// members (X).
        case typeReference
        /// A family no member of which has a primary USR (W).
        case unjudged
        /// A family not among the snapshot's records (U).
        case unknownFamily
    }

    /// The limits a listed pair meets.
    struct Limits {
        /// Commits in the window changing both families, at least.
        let support: Double
        /// Support as a percent of the less-changed family's changes, at
        /// least.
        let confidence: Double

        /// The limits `thresholds` set.
        init(_ thresholds: SignalThresholds) {
            let signal = SignalThresholds.hiddenCoupling
            support = thresholds.limit(SignalThresholds.support, of: signal) ?? 0
            confidence = thresholds.limit(SignalThresholds.confidence, of: signal) ?? 0
        }
    }

    /// A coupling pair with what the signal decides of it.
    struct Judged {
        /// The pair.
        let pair: CouplingPair
        /// What the signal decides of it.
        let verdict: Verdict
        /// The snapshot's family the pair names first; nil when there is
        /// none.
        let first: FunctionFamily?
        /// The family it names second; nil when there is none.
        let second: FunctionFamily?
    }

    /// What judging the pairs counted.
    struct Tally: Hashable {
        /// The pairs with each verdict.
        private(set) var counts: [Verdict: Int] = [:]
        /// Every pair.
        private(set) var pairs = 0

        /// The pairs with both families in production code.
        var production: Int {
            pairs - count(.unknownFamily) - count(.generated) - count(.nonProduction)
        }

        /// Of those, the pairs judged: each family has a primary USR.
        var judged: Int {
            production - count(.unjudged)
        }

        /// Of those, the pairs without a static dependency.
        var withoutDependency: Int {
            count(.listed) + count(.belowLimits)
        }

        /// `verdicts` counted.
        init(_ verdicts: [Verdict]) {
            pairs = verdicts.count
            for verdict in verdicts {
                counts[verdict, default: 0] += 1
            }
        }

        /// The pairs with `verdict`.
        func count(_ verdict: Verdict) -> Int {
            counts[verdict] ?? 0
        }
    }

    /// The history collector's option recording the support pairs are cut
    /// at, before its value.
    private static let minimumSupportOption = "coupling.min_support: "

    /// The rule as reports state it with `thresholds`, before the funnel.
    static func rule(thresholds: SignalThresholds) -> String {
        let limits = Limits(thresholds)
        let support = MarkdownNumber.exact(limits.support)
        let confidence = MarkdownNumber.exact(limits.confidence)
        return "pairs of production families changed together by at least \(support) commits in the window "
            + "(confidence at least \(confidence)%: support ÷ the less-changed family's changes) with no static "
            + "dependency: neither references the other (index: calls, reads, writes, directly or through a "
            + "protocol requirement the other witnesses), they don't share or nest a package type, and neither "
            + "references the other's type or its members; same file or module isn't a dependency; candidates for "
            + "an explicit abstraction"
    }

    /// The signal over `inputs` with the limits `thresholds` set; nil when
    /// the snapshot holds no index results.
    static func compute(_ inputs: SignalInputs, thresholds: SignalThresholds) -> SignalComputation? {
        let snapshot = inputs.snapshot
        guard let index = snapshot.index?.report else {
            return nil
        }
        let limits = Limits(thresholds)
        let judged = judged(snapshot, pairs: snapshot.couplingPairs, index: index, limits: limits)
        let scored = judged.compactMap { entry -> SignalScore? in
            guard entry.verdict == .listed, let first = entry.first, let second = entry.second else {
                return nil
            }
            return item(entry.pair, first: first, second: second)
        }
        let tally = Tally(judged.map(\.verdict))
        return SignalComputation(
            rule: rule(thresholds: thresholds) + "; " + funnel(tally)
                + note(limits, minimumSupport: minimumSupport(snapshot)),
            candidates: tally.pairs,
            scored: scored
        )
    }

    /// `pairs` judged over `snapshot`'s families and `index`, its index
    /// results, with `limits`, in the pairs' order.
    static func judged(
        _ snapshot: StoredSnapshot,
        pairs: [CouplingPair],
        index: IndexReport,
        limits: Limits
    ) -> [Judged] {
        let families = Dictionary(grouping: FunctionFamily.families(snapshot.functions), by: \.id)
        let withUSR = Set(index.records.filter { $0.usr != nil }.map(\.key))
        let references = Set(index.familyReferences)
        let typeReferences = Set(index.familyTypeReferences)
        let owners = CouplingOwners(index: index)
        return pairs.map { pair in
            let first = family(pair.familyA, file: pair.fileA, in: families)
            let second = family(pair.familyB, file: pair.fileB, in: families)
            guard let first, let second else {
                return Judged(pair: pair, verdict: .unknownFamily, first: first, second: second)
            }
            let verdict: Verdict
            if isGenerated(first) || isGenerated(second) {
                verdict = .generated
            } else if role(of: first) != .production || role(of: second) != .production {
                verdict = .nonProduction
            } else if [first, second].contains(where: { family in
                family.members.allSatisfy { withUSR.contains($0.key) == false }
            }) {
                verdict = .unjudged
            } else {
                verdict = dependency(first, second, references: references, types: typeReferences, owners: owners)
                    ?? (isListed(pair, limits: limits) ? .listed : .belowLimits)
            }
            return Judged(pair: pair, verdict: verdict, first: first, second: second)
        }
    }

    /// The funnel from the pairs to the listed ones, each part summing to
    /// its whole.
    static func funnel(_ tally: Tally) -> String {
        let production = tally.production
        let judged = tally.judged
        let without = tally.withoutDependency
        return "\(tally.pairs) pairs = \(tally.count(.unknownFamily)) with a family not in this snapshot + "
            + "\(tally.count(.generated)) with a generated family + \(tally.count(.nonProduction)) with a test or "
            + "helper family + \(production) with both families in production code; \(production) = \(judged) "
            + "judged + \(tally.count(.unjudged)) with a family the index didn't see; \(judged) = "
            + "\(tally.count(.references)) referencing each other + \(tally.count(.requirement)) calling through a "
            + "protocol the other implements + \(tally.count(.sharedType)) sharing or nesting a type + "
            + "\(tally.count(.typeReference)) referencing the other's type or members + \(without) without a static "
            + "dependency; \(without) = \(tally.count(.listed)) listed + \(tally.count(.belowLimits)) below the limits"
    }

    /// What the rule adds after the funnel when the support limit is below
    /// `minimumSupport`, the support history cut the pairs at: that pairs
    /// below it don't exist; nothing otherwise, or when it isn't known.
    static func note(_ limits: Limits, minimumSupport: Int?) -> String {
        guard let minimumSupport, limits.support < Double(minimumSupport) else {
            return ""
        }
        return "; pairs exist only at or above history.coupling.min_support (\(minimumSupport))"
    }

    /// The support `snapshot`'s history cut its pairs at, as its history
    /// run records it; nil when it records none.
    static func minimumSupport(_ snapshot: StoredSnapshot) -> Int? {
        let run = snapshot.info.collectors.first { $0.name == HistoryCollector.name }
        return run?.options.lazy
            .filter { $0.hasPrefix(minimumSupportOption) }
            .compactMap { Int($0.dropFirst(minimumSupportOption.count)) }
            .first
    }

    /// The family named `identifier` among `families` (by key): the one in
    /// `file` when several share the key, else the first; nil when none
    /// has it.
    private static func family(
        _ identifier: String,
        file: String,
        in families: [String: [FunctionFamily]]
    ) -> FunctionFamily? {
        let named = families[identifier] ?? []
        return named.first { $0.file == file } ?? named.first
    }

    /// Whether a member of `family` is in a generated file.
    private static func isGenerated(_ family: FunctionFamily) -> Bool {
        family.members.contains { $0.facts?.generated == true }
    }

    /// The role of `family`'s root, or of a computed property's first
    /// accessor.
    private static func role(of family: FunctionFamily) -> CodeRole {
        (family.root ?? family.members[0]).role
    }

    /// The first static dependency between `first` and `second`, by
    /// `references` and `types` (the index's family references and family
    /// type references) and the roots' `owners`; nil when there is none.
    private static func dependency(
        _ first: FunctionFamily,
        _ second: FunctionFamily,
        references: Set<IndexFamilyReference>,
        types: Set<IndexFamilyTypeReference>,
        owners: CouplingOwners
    ) -> Verdict? {
        let referencing = { (via: IndexFamilyReference.Via) in
            references.contains(IndexFamilyReference(fromFamily: first.id, toFamily: second.id, via: via))
                || references.contains(IndexFamilyReference(fromFamily: second.id, toFamily: first.id, via: via))
        }
        if referencing(.direct) {
            return .references
        }
        if referencing(.requirement) {
            return .requirement
        }
        let firstOwner = owners.owner(of: first)
        let secondOwner = owners.owner(of: second)
        if let firstOwner, let secondOwner,
           firstOwner == secondOwner || CouplingOwners.isNested(firstOwner, secondOwner) {
            return .sharedType
        }
        let referencesType = { (family: FunctionFamily, owner: TypeIdentity?) in
            guard let owner else {
                return false
            }
            return types.contains(IndexFamilyTypeReference(
                family: family.id,
                module: owner.module,
                typePath: owner.typePath,
                typeFile: owner.writtenFile
            ))
        }
        return referencesType(first, secondOwner) || referencesType(second, firstOwner) ? .typeReference : nil
    }

    /// Whether `pair` reaches `limits`: its support, and its support as a
    /// percent of the less-changed family's changes, compared exactly
    /// (`PercentLimit`).
    private static func isListed(_ pair: CouplingPair, limits: Limits) -> Bool {
        Double(pair.support) >= limits.support
            && PercentLimit.reaches(pair.support, of: min(pair.changesA, pair.changesB), limit: limits.confidence)
    }

    /// The item for `pair`, listed, whose families are `first` and
    /// `second`.
    private static func item(_ pair: CouplingPair, first: FunctionFamily, second: FunctionFamily) -> SignalScore {
        let smaller = min(pair.changesA, pair.changesB)
        let draft = SignalItem.Draft(
            subject: pair.familyA,
            file: pair.fileA,
            line: first.startLine,
            coupling: SignalItem.Coupling(
                partner: pair.familyB,
                partnerFile: pair.fileB,
                support: pair.support,
                changesA: pair.changesA,
                changesB: pair.changesB,
                confidence: SignalItem.CouplingConfidence(support: pair.support, smaller: smaller),
                modules: [first.module, second.module],
                sameFile: pair.fileA == pair.fileB,
                sameModule: first.module == second.module
            )
        )
        let support = Double(pair.support)
        let order = SignalSortKey([
            .number(-support),
            .fraction(smaller, of: max(pair.support, 1)),
            .text(pair.familyA),
            .text(pair.fileA),
            .number(Double(first.startLine)),
            .text(pair.familyB),
            .text(pair.fileB)
        ])
        return SignalScore(draft, score: support, sortKey: order)
    }
}

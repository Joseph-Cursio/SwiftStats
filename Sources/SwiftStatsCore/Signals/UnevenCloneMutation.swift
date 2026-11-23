//
//  UnevenCloneMutation.swift
//  SwiftStatsCore
//
//  Uneven clone testing, mutation part (PRD §8, M6, design §7.4, U12):
//  copies of one piece of code whose mutants the tests kill unevenly, so a
//  copy's tests could be copied or the code merged. A copy's mutants are
//  every mapped mutant of its file (placed on a record, a type or the
//  file) whose anchor lies in the copy's inclusive range, so a mutant
//  SwiftMutator points past a copy's last statement still counts for it;
//  its function score counts code no test ran as unkilled. A copy in a
//  generated file (which the clone tool isn't given), in a file whose
//  results are unresolved or unlisted after a merge, or with fewer than
//  `signals.uneven-clone-mutation.mutants` scored mutants (2), is skipped
//  and counted. The pool is the clone classes with two or more measured
//  copies. A class is listed when one copy's function score is at least
//  `high` (80%) and another's at most `low` (20%), scored by the unkilled
//  mutants of its copies at most `low`, and named by its least killed
//  copy's family. Classes whose poorly tested copies hold a mutant that
//  ran and wasn't checked come first; the rest, unkilled only through code
//  no test ran, are the evidence uneven clone testing's coverage part
//  already shows. A listed class whose poorly tested copies all lie inside
//  another listed class's folds into it (`CloneFolding`). Each item counts
//  its own mutants, so the rule says how many more than one item counts.
//  The signal isn't ranked.
//

/// The uneven clone testing (mutation) signal.
enum UnevenCloneMutation {
    /// The limits of an uneven clone mutation judgement.
    struct Limits {
        /// A well tested copy's function score at least, in percent.
        let high: Double
        /// A poorly tested copy's function score at most, in percent.
        let low: Double
        /// A measured copy's scored mutants at least.
        let mutants: Int

        /// The limits `thresholds` set.
        init(_ thresholds: SignalThresholds) {
            let signal = SignalThresholds.unevenCloneMutation
            high = thresholds.limit(SignalThresholds.high, of: signal) ?? 0
            low = thresholds.limit(SignalThresholds.low, of: signal) ?? 0
            mutants = Int(thresholds.limit(SignalThresholds.mutants, of: signal) ?? 0)
        }
    }

    /// What judging the clone classes counted.
    private struct Tally {
        /// The clone classes.
        var classes = 0
        /// Every copy of every class.
        var copies = 0
        /// Copies in generated files.
        var inGenerated = 0
        /// Copies in files whose results are unresolved or unlisted.
        var withoutResults = 0
        /// Copies with fewer scored mutants than the fewest.
        var fewMutants = 0
        /// Classes with fewer than two measured copies.
        var fewCopies = 0
    }

    /// The rule as reports state it with `thresholds`, before the funnel.
    static func rule(thresholds: SignalThresholds) -> String {
        let limits = Limits(thresholds)
        let high = MarkdownNumber.exact(limits.high)
        let low = MarkdownNumber.exact(limits.low)
        return "clone classes with a copy at least \(high)% and a copy at most \(low)% of its mutants killed (code "
            + "no test ran counting as unkilled), copies with at least \(MutationPool.scored(limits.mutants)) "
            + "(build errors aside); scored by the unkilled mutants of the copies at most \(low)% killed; classes "
            + "whose poorly tested copies hold a mutant that ran and wasn't checked come first"
    }

    /// The signal over `snapshot` with `thresholds`; nil when it holds no
    /// mutation results.
    static func compute(_ snapshot: StoredSnapshot, thresholds: SignalThresholds) -> SignalComputation? {
        guard let mutation = snapshot.mutation?.report else {
            return nil
        }
        let limits = Limits(thresholds)
        let judge = MutationJudge(snapshot, mutation: mutation, coverage: nil)
        let index = FamilyIndex(snapshot.functions)
        let generated = Set(snapshot.functions.filter { $0.facts?.generated == true }.map(\.file))
        var tally = Tally(classes: snapshot.cloneClasses.count)
        var members: [UnevenMutationMember] = []
        for cloneClass in snapshot.cloneClasses {
            var copies: [MutationCopy] = []
            for instance in cloneClass.instances {
                tally.copies += 1
                if generated.contains(instance.file) {
                    tally.inGenerated += 1
                } else if Self.lacksResults(judge.disposition(of: instance.file)) {
                    tally.withoutResults += 1
                } else {
                    let copy = MutationCopy(
                        instance: instance,
                        mutants: judge.mutants(in: instance.file, range: instance.range),
                        family: family(of: instance, index: index)
                    )
                    if copy.score.scored >= limits.mutants {
                        copies.append(copy)
                    } else {
                        tally.fewMutants += 1
                    }
                }
            }
            guard copies.count >= UnevenCloneTesting.minimumCopies else {
                tally.fewCopies += 1
                continue
            }
            let poor = copies.filter { MutationPool.isAtMost($0.score, limits.low) }
            if poor.isEmpty == false, copies.contains(where: { MutationPool.isAtLeast($0.score, limits.high) }) {
                members.append(UnevenMutationMember(cloneClass: cloneClass, copies: copies, poor: poor))
            }
        }
        let kept = CloneFolding.folded(members, cloneClass: \.cloneClass) { $0.holds($1) }
        let notes = mutation.listsNotCovered ? "" : "; " + WeakTests.notListedNote
        return SignalComputation(
            rule: rule(thresholds: thresholds) + "; " + funnel(tally, members: members, kept: kept, limits: limits)
                + notes,
            candidates: snapshot.cloneClasses.count - tally.fewCopies,
            scored: kept.map { item($0.member, folded: $0.folded) }
        )
    }

    /// Whether a file whose results are `disposition` lacks full results:
    /// unresolved or unlisted after a merge.
    private static func lacksResults(_ disposition: MutationFileDisposition?) -> Bool {
        disposition == .unresolved || disposition == .unlisted
    }

    /// The family naming `instance`, by M4's copy-to-family rule;
    /// `<file>:<line>` when no family holds it.
    private static func family(of instance: CloneInstance, index: FamilyIndex) -> String {
        index.units(of: instance).first?.family.id ?? "\(instance.file):\(instance.range.start.line)"
    }

    /// The funnel from the classes' copies to the listed items, each part
    /// summing to its whole, with the classes folded and the mutants more
    /// than one item counts.
    private static func funnel(
        _ tally: Tally,
        members: [UnevenMutationMember],
        kept: [(member: UnevenMutationMember, folded: [Int])],
        limits: Limits
    ) -> String {
        let uneven = members.count
        let pooled = tally.classes - tally.fewCopies
        let measured = tally.copies - tally.inGenerated - tally.withoutResults - tally.fewMutants
        let foldedCount = kept.reduce(0) { $0 + $1.folded.count }
        let unchecked = kept.count { $0.member.ranUnchecked }
        let counting = Dictionary(kept.flatMap { $0.member.unkilled.map { ($0.key, 1) } }, uniquingKeysWith: +)
        let shared = counting.values.count { $0 > 1 }
        let high = MarkdownNumber.exact(limits.high)
        let low = MarkdownNumber.exact(limits.low)
        return "\(counted(tally.copies, "copy", "copies")) of \(counted(tally.classes, "class", "classes")) = "
            + "\(tally.inGenerated) in generated files + \(tally.withoutResults) in files without full results "
            + "(unresolved or unlisted) + \(tally.fewMutants) with fewer than \(MutationPool.scored(limits.mutants)) "
            + "+ \(measured) measured; \(tally.classes) = \(pooled) with at least \(UnevenCloneTesting.minimumCopies) "
            + "measured copies + \(tally.fewCopies) with fewer; \(pooled) = \(uneven) with a copy at least \(high)% "
            + "and one at most \(low)% killed + \(pooled - uneven) without; \(uneven) = \(kept.count) listed + "
            + "\(foldedCount) folded into a listed class; \(kept.count) = \(unchecked) with a mutant that ran and "
            + "wasn't checked + \(kept.count - unchecked) unkilled only through code no test ran (the same evidence "
            + "as uneven clone testing's coverage part); \(counted(shared, "mutant", "mutants")) counted by more "
            + "than one item"
    }

    /// The item for `member`, about its least killed copy, with the
    /// ordinals of the classes folded into it.
    private static func item(_ member: UnevenMutationMember, folded: [Int]) -> SignalScore {
        let subject = member.leastKilled
        let cloneClass = member.cloneClass
        let draft = SignalItem.Draft(
            subject: subject.family,
            file: subject.file,
            line: subject.start,
            clone: SignalItem.Clone(
                ordinal: cloneClass.ordinal,
                pass: cloneClass.pass,
                exact: cloneClass.exact,
                mass: cloneClass.mass,
                lines: member.poor.reduce(0) { $0 + $1.instance.strippedLines },
                copies: member.copies.count,
                churn: nil,
                divergence: nil,
                coverage: nil,
                mutation: SignalItem.CloneMutation(folded: folded, copies: member.copies.map(\.listed))
            )
        )
        let score = Double(member.unkilled.count)
        let order = SignalSortKey([
            .number(member.ranUnchecked ? 0 : 1),
            .number(-score),
            .number(-Double(cloneClass.mass)),
            .number(Double(CloneKind(pass: cloneClass.pass, exact: cloneClass.exact).rank)),
            .text(subject.family),
            .text(subject.file),
            .number(Double(subject.start)),
            .number(Double(cloneClass.ordinal))
        ])
        return SignalScore(draft, score: score, sortKey: order)
    }

    /// `count` and `singular`, or `plural` unless `count` is 1.
    private static func counted(_ count: Int, _ singular: String, _ plural: String) -> String {
        count == 1 ? "1 \(singular)" : "\(count) \(plural)"
    }
}

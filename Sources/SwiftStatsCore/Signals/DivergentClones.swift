//
//  DivergentClones.swift
//  SwiftStatsCore
//
//  Divergent clones (PRD §8): copies of one piece of code where one copy
//  changed since an earlier snapshot and another didn't, perhaps a fix
//  made in one place only. The pool is the earlier snapshot's clone
//  classes with two or more copies whose units all match a production
//  family outside generated files with known history now. A unit changed
//  when a non-sweep commit since then changed its family and a hunk of
//  the diff since then lies in its lines; so an edit elsewhere in the
//  host, a sweep, or an edit later reverted reads as unchanged. Units
//  pair into slots across copies: by position for subtree and sequence
//  classes with equal unit counts, else by signature when a copy has
//  several, else one slot of each copy's unit. A class is listed when a
//  slot has a changed and an unchanged unit, scored by those slots' lines
//  per copy beyond the first; nested classes fold into the class holding
//  them. The signal isn't ranked.
//

/// The divergent-clones signal.
enum DivergentClones {
    /// Why the signal is left out when no earlier snapshot has clone data.
    static let noEarlier = "no earlier snapshot with clone data; scan an older commit (`swiftstats diff <rev>`) "
        + "or `backfill --with-tools`"

    /// The fewest copies with a family now that put a class in the pool.
    static let minimumCopies = 2

    /// The rule as reports state it, before the classes are counted.
    static let rule = "clone classes of an earlier snapshot with a copy changed since (a non-sweep commit to "
        + "its family and a diff hunk in its lines) and a copy unchanged"

    /// The signal over `inputs`; nil without an earlier snapshot.
    static func compute(_ inputs: SignalInputs) -> SignalComputation? {
        guard let earlier = inputs.earlier else {
            return nil
        }
        let sinceCommit = earlier.info.git.commit ?? ""
        let old = FamilyIndex(earlier.functions)
        let matched = Dictionary(
            FamilyMatcher.match(old: old.families, new: FamilyIndex(inputs.snapshot.functions).families)
                .matches.map { ($0.old.identity, $0.new) }
        ) { first, _ in first }
        let history = FamilyCommits(inputs.snapshot)
        var skipped = 0
        var pool = 0
        var members: [DivergentMember] = []
        for cloneClass in earlier.cloneClasses {
            let copies = cloneClass.instances.map { instance in
                copyUnits(
                    old.units(of: instance),
                    matched: matched,
                    history: history,
                    since: inputs.since,
                    hunks: inputs.hunks[instance.file] ?? []
                )
            }
            .filter { $0.isEmpty == false }
            skipped += cloneClass.instances.count - copies.count
            guard copies.count >= minimumCopies else {
                continue
            }
            pool += 1
            if let member = member(cloneClass, copies: copies) {
                members.append(member)
            }
        }
        let kept = folded(members)
        let foldedCount = kept.reduce(0) { $0 + $1.folded.count }
        let since = inputs.earlierNote ?? String(sinceCommit.prefix(MarkdownSignals.shortLength))
        return SignalComputation(
            rule: rule + "; since \(since); \(skipped) copies with no production family outside generated "
                + "files with known history now are skipped; \(foldedCount) classes nested in a listed one are "
                + "folded into it",
            candidates: pool,
            scored: kept.map { item($0.member, folded: $0.folded, sinceCommit: sinceCommit) }
        )
    }

    /// The units of a copy matched to their families now, with whether
    /// each changed; none when the copy has none, or when a unit has no
    /// production family outside generated files now, or one whose history
    /// isn't known (uncommitted), so the copy is skipped rather than read
    /// as unchanged.
    private static func copyUnits(
        _ units: [CloneUnit],
        matched: [String: FunctionFamily],
        history: FamilyCommits,
        since: Set<String>,
        hunks: [DiffHunk]
    ) -> [CopyUnit] {
        var copy: [CopyUnit] = []
        for unit in units {
            guard let family = matched[unit.family.identity],
                  history.isProduction(family),
                  history.row(FamilyRef(family))?.changes != nil else {
                return []
            }
            let commits = history.commits(of: FamilyRef(family)).filter { since.contains($0.hash) }
            let touched = hunks.contains { $0.overlaps(lower: unit.start, upper: unit.end) }
            let changed = commits.isEmpty == false && touched
            copy.append(CopyUnit(unit: unit, family: family, commits: commits, changed: changed))
        }
        return copy
    }

    /// `cloneClass` as a member, when one of its slots has a changed and an
    /// unchanged unit; nil when none does.
    private static func member(_ cloneClass: CloneClass, copies: [[CopyUnit]]) -> DivergentMember? {
        let diverging = slots(cloneClass.pass, copies: copies).filter { slot in
            slot.contains(where: \.changed) && slot.contains { $0.changed == false }
        }
        guard diverging.isEmpty == false else {
            return nil
        }
        // Copy by copy, so the lists read in the copies' order.
        let units = copies.indices.flatMap { index in diverging.map { $0[index] } }
        return DivergentMember(
            cloneClass: cloneClass,
            copies: copies.count,
            lines: units.reduce(0) { $0 + $1.unit.lines },
            changed: unique(units.filter(\.changed)),
            unchanged: unique(units.filter { $0.changed == false })
        )
    }

    /// The slots of a class's copies, each holding one unit per copy in
    /// copy order: by position for subtree and sequence classes whose
    /// copies have equal unit counts; else, when a copy has several units,
    /// by signature, a unit without one partner in every other copy taking
    /// no slot; else one slot of each copy's unit.
    private static func slots(_ pass: CloneClass.Pass, copies: [[CopyUnit]]) -> [[CopyUnit]] {
        let counts = Set(copies.map(\.count))
        if pass != .nearMiss, counts.count == 1, let count = counts.first {
            return (0..<count).map { position in copies.map { $0[position] } }
        }
        guard copies.contains(where: { $0.count > 1 }), let first = copies.first else {
            return [copies.compactMap(\.first)]
        }
        let bySignature = copies.map { copy in Dictionary(grouping: copy, by: \.unit.signature) }
        return first
            .map { unit in
                bySignature.compactMap { units -> CopyUnit? in
                    guard let found = units[unit.unit.signature], found.count == 1 else {
                        return nil
                    }
                    return found[0]
                }
            }
            .filter { $0.count == copies.count }
    }

    /// `units` with each family once, in order.
    private static func unique(_ units: [CopyUnit]) -> [CopyUnit] {
        var seen: Set<FamilyRef> = []
        return units.filter { seen.insert($0.ref).inserted }
    }

    /// The item for `member`, about its first unchanged copy, with the
    /// earlier ordinals of the classes folded into it.
    private static func item(_ member: DivergentMember, folded: [Int], sinceCommit: String) -> SignalScore {
        let subject = member.unchanged[0].family
        let cloneClass = member.cloneClass
        let draft = SignalItem.Draft(
            subject: subject.id,
            file: subject.file,
            line: subject.startLine,
            clone: SignalItem.Clone(
                ordinal: cloneClass.ordinal,
                pass: cloneClass.pass,
                exact: cloneClass.exact,
                mass: cloneClass.mass,
                lines: member.lines,
                copies: member.copies,
                churn: nil,
                divergence: SignalItem.Divergence(
                    sinceCommit: sinceCommit,
                    folded: folded,
                    changed: member.changed.map(\.copy),
                    unchanged: member.unchanged.map(\.copy)
                )
            )
        )
        let order = SignalSortKey([
            .number(-member.score),
            .number(-Double(cloneClass.mass)),
            .number(Double(member.kind.rank)),
            .text(subject.id),
            .text(subject.file),
            .number(Double(subject.startLine)),
            .number(Double(cloneClass.ordinal))
        ])
        return SignalScore(draft, score: member.score, sortKey: order)
    }
}

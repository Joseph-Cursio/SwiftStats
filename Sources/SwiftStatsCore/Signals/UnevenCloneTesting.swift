//
//  UnevenCloneTesting.swift
//  SwiftStatsCore
//
//  Uneven clone testing, coverage part (PRD §8, M5): copies of one piece
//  of code that the tests cover unevenly, so a copy's tests could be copied
//  or the code merged. A copy's coverage is the file's line data over its
//  inclusive range, covered of mapped lines; a copy with no mapped line, or
//  in a generated file (which the clone tool isn't given), is skipped and
//  counted. The pool is the snapshot's clone classes with two or more
//  measurable copies. A class is listed when one copy is at
//  least 80% covered and another at most 20%, scored by the uncovered
//  mapped lines of its copies at most 20% covered, and named by its least
//  covered copy's family. A listed class whose poorly covered copies all
//  lie inside another listed class's folds into it (`CloneFolding`). Each
//  item counts its own lines, so the rule says how many uncovered lines
//  more than one item counts. The signal isn't ranked.
//

/// The uneven-clone-testing signal.
enum UnevenCloneTesting {
    /// The share of its mapped lines a well covered copy has run, at least.
    static let wellCovered = 0.8
    /// The share of its mapped lines a poorly covered copy has run, at most.
    static let poorlyCovered = 0.2
    /// The fewest measurable copies that put a class in the pool.
    static let minimumCopies = 2

    /// The rule as reports state it, before the classes are counted.
    static let rule = "clone classes with a copy at least 80% and a copy at most 20% of its mapped lines covered, "
        + "scored by the uncovered mapped lines of the copies at most 20% covered"

    /// The signal over `snapshot`; nil when it holds no coverage.
    static func compute(_ snapshot: StoredSnapshot) -> SignalComputation? {
        guard let coverage = snapshot.coverage?.report else {
            return nil
        }
        let lines = CoverageLines(coverage)
        let index = FamilyIndex(snapshot.functions)
        let generated = Set(snapshot.functions.filter { $0.facts?.generated == true }.map(\.file))
        var inGenerated = 0
        var skipped = 0
        var fewCopies = 0
        var members: [UnevenMember] = []
        for cloneClass in snapshot.cloneClasses {
            let outside = cloneClass.instances.filter { generated.contains($0.file) == false }
            let copies = outside.compactMap { measured($0, lines: lines, index: index) }
            inGenerated += cloneClass.instances.count - outside.count
            skipped += outside.count - copies.count
            guard copies.count >= minimumCopies else {
                fewCopies += 1
                continue
            }
            let poor = copies.filter { $0.share <= poorlyCovered }
            if poor.isEmpty == false, copies.contains(where: { $0.share >= wellCovered }) {
                members.append(UnevenMember(cloneClass: cloneClass, copies: copies, poor: poor))
            }
        }
        let kept = CloneFolding.folded(members, cloneClass: \.cloneClass) { $0.holds($1) }
        let foldedCount = kept.reduce(0) { $0 + $1.folded.count }
        let counted = kept.flatMap(\.member.uncovered)
        let shared = Dictionary(grouping: counted) { $0 }.values.filter { $0.count > 1 }.count
        let pool = snapshot.cloneClasses.count - fewCopies
        return SignalComputation(
            rule: rule + "; \(inGenerated) copies in generated files and \(skipped) copies with no mapped line are "
                + "skipped, leaving \(fewCopies) classes with fewer than \(minimumCopies) measurable copies out; "
                + "\(foldedCount) classes whose poorly covered copies lie inside a listed class's are folded into it; "
                + "\(shared) uncovered lines are counted by more than one item",
            candidates: pool,
            scored: kept.map { item($0.member, folded: $0.folded) }
        )
    }

    /// `instance` with its line coverage; nil when it has no mapped line.
    private static func measured(_ instance: CloneInstance, lines: CoverageLines, index: FamilyIndex) -> MeasuredCopy? {
        let range = instance.range.start.line...instance.range.end.line
        let tally = lines.tally(instance.file, lines: range)
        guard tally.total > 0 else {
            return nil
        }
        let family = index.units(of: instance).first?.family.id ?? "\(instance.file):\(range.lowerBound)"
        return MeasuredCopy(
            instance: instance,
            tally: tally,
            uncovered: lines.uncovered(instance.file, lines: range),
            family: family
        )
    }

    /// The item for `member`, about its least covered copy, with the
    /// ordinals of the classes folded into it.
    private static func item(_ member: UnevenMember, folded: [Int]) -> SignalScore {
        let subject = member.leastCovered
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
                coverage: SignalItem.CloneCoverage(folded: folded, copies: member.copies.map(\.listed)),
                mutation: nil
            )
        )
        let score = Double(member.uncovered.count)
        let order = SignalSortKey([
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
}

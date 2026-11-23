//
//  CloneHotspot.swift
//  SwiftStatsCore
//
//  Clone hotspot (PRD §8): duplicated code that keeps changing, where
//  every change may have to be made in each copy. The pool is the
//  snapshot's clone classes whose every copy is whole functions, or
//  covers at least 80% of the family holding it (the outermost function,
//  or a computed property's accessors), whose commits it would score; and
//  whose families are production code outside generated files with known
//  history. A class of smaller fragments says more about its host than
//  about the copy, and is left out and counted. A class scores the distinct
//  non-sweep commits in the window that changed any of its families, so a
//  commit changing every copy counts once. The signal is ranked.
//

/// The clone-hotspot signal.
enum CloneHotspot {
    /// The least share of its family's stripped lines a fragment copy covers.
    static let minimumCoverage = 0.8

    /// The rule as reports state it, over `count` classes when given.
    static func rule(thresholds: SignalThresholds, count: Int?) -> String {
        let percent = MarkdownNumber.exact(thresholds.percent(for: SignalName.cloneHotspot.rawValue))
        let classes = count.map { "\($0) classes" } ?? "classes"
        return "top \(percent)% of \(classes) by distinct non-sweep commits in the window changing their copies"
    }

    /// The signal over `snapshot`; nil when it has no history.
    static func compute(_ snapshot: StoredSnapshot, thresholds: SignalThresholds) -> SignalComputation? {
        guard let run = snapshot.history else {
            return nil
        }
        let index = FamilyIndex(snapshot.functions)
        let history = FamilyCommits(snapshot)
        var fragments = 0
        var scored: [SignalScore] = []
        var pool = 0
        for cloneClass in snapshot.cloneClasses {
            let copies = cloneClass.instances.map { index.units(of: $0) }
            guard zip(cloneClass.instances, copies).allSatisfy({ isCovered($0, units: $1) }) else {
                fragments += 1
                continue
            }
            let families = copies.flatMap(\.self).map(\.family)
            guard families.allSatisfy({ isTraced($0, history: history) }) else {
                continue
            }
            pool += 1
            let commits = Set(families.flatMap { history.commits(of: FamilyRef($0)) }
                .filter { $0.date >= run.windowStart }
                .map(\.hash))
            scored.append(item(cloneClass, first: families[0], churn: commits.count))
        }
        let leftOut = "; \(fragments) classes with a copy covering under \(Int(minimumCoverage * 100))% of its "
            + "function are left out"
        return SignalComputation(
            rule: rule(thresholds: thresholds, count: pool) + leftOut,
            candidates: pool,
            scored: scored
        )
    }

    /// Whether `instance` is whole functions, or covers enough of the
    /// family holding it: the family whose commits the class would score,
    /// not the innermost record, so a copy that is a whole nested function
    /// or one accessor of several doesn't score its host's churn.
    private static func isCovered(_ instance: CloneInstance, units: [CloneUnit]) -> Bool {
        guard let first = units.first else {
            return false
        }
        guard first.whole == false else {
            return true
        }
        return Double(instance.strippedLines) / Double(max(first.family.strippedLines, 1)) >= minimumCoverage
    }

    /// Whether `family` is production code outside generated files whose
    /// history is known.
    private static func isTraced(_ family: FunctionFamily, history: FamilyCommits) -> Bool {
        history.isProduction(family) && history.row(FamilyRef(family))?.changes != nil
    }

    /// The item for `cloneClass`, about the first family of its first
    /// copy, where that copy starts.
    private static func item(_ cloneClass: CloneClass, first: FunctionFamily, churn: Int) -> SignalScore {
        let instance = cloneClass.instances[0]
        let draft = SignalItem.Draft(
            subject: first.id,
            file: instance.file,
            line: instance.range.start.line,
            clone: SignalItem.Clone(
                ordinal: cloneClass.ordinal,
                pass: cloneClass.pass,
                exact: cloneClass.exact,
                mass: cloneClass.mass,
                lines: cloneClass.instances.reduce(0) { $0 + $1.strippedLines },
                copies: cloneClass.instances.count,
                churn: churn,
                divergence: nil,
                coverage: nil
            )
        )
        let score = Double(churn)
        let order = SignalSortKey.standard(score: score, subject: draft.subject, file: draft.file, line: draft.line)
            .appending(.number(Double(cloneClass.ordinal)))
        return SignalScore(draft, score: score, sortKey: order)
    }
}

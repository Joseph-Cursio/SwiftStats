//
//  HistorySignals.swift
//  SwiftStatsCore
//
//  M3's signals (PRD §8): hotspots, bug-prone, unstable fixes, tests not
//  keeping up and safe to leave. Their pool is the production families
//  outside generated files whose history is known; each scores a family
//  from its history in the window, and lists the families scoring above
//  zero by score, highest first.
//

/// The signals computed from history.
enum HistorySignals {
    /// One family in the pool, with its inputs.
    struct Candidate {
        /// Its history row.
        let history: FamilyHistoryRow
        /// Its cognitive complexity.
        let cognitive: Int?
        /// Commits in the window that changed it, sweeps aside.
        let changes: Int
    }

    /// The fewest changes in the window for "tests not keeping up".
    static let minimumChanges = 3
    /// The share of changes with a test change below which tests aren't keeping up.
    static let testChangeShare = 0.25

    /// `signal` over `pool`, the families of `snapshot`; nil when the
    /// snapshot has no history.
    static func compute(
        _ signal: SignalName,
        pool: [Candidate],
        snapshot: StoredSnapshot,
        thresholds: SignalThresholds
    ) -> SignalComputation? {
        guard let run = snapshot.history else {
            return nil
        }
        return SignalComputation(
            rule: rule(for: signal, thresholds: thresholds, count: pool.count),
            candidates: pool.count,
            scored: pool.compactMap { candidate in
                score(signal, candidate, windowStart: run.windowStart).map { value in
                    SignalScore(item(candidate), score: value)
                }
            }
        )
    }

    /// Production families outside generated files with known history.
    static func pool(_ snapshot: StoredSnapshot) -> [Candidate] {
        let families = Dictionary(
            FunctionFamily.families(snapshot.functions).map { (FamilyRef($0), $0) }
        ) { first, _ in first }
        return snapshot.familyHistory.compactMap { history in
            guard history.generated == false, let changes = history.changes,
                  let family = families[FamilyRef(id: history.family, file: history.file)] else {
                return nil
            }
            guard (family.root ?? family.accessors.first)?.role == .production else {
                return nil
            }
            return Candidate(history: history, cognitive: cognitive(of: family), changes: changes)
        }
    }

    /// A family's cognitive complexity: its root's, or, for a root that has
    /// none of its own (a subscript with explicit accessors), its direct
    /// accessors' highest; a computed property's accessors' highest.
    static func cognitive(of family: FunctionFamily) -> Int? {
        guard let root = family.root else {
            return family.accessors.compactMap(\.cognitive).max()
        }
        if let own = root.cognitive {
            return own
        }
        return family.members
            .filter { $0.kind == .accessor && $0.parentKey == root.key }
            .compactMap(\.cognitive)
            .max()
    }

    /// The membership rule as reports state it, over `count` candidates;
    /// empty for a signal not computed from history, which states its own.
    static func rule(for signal: SignalName, thresholds: SignalThresholds, count: Int) -> String {
        switch signal {
        case .bugProne:
            "top \(MarkdownNumber.value(thresholds.percent(for: signal.rawValue)))% of \(count) candidates "
                + "by age-weighted fixes"

        case .hotspot:
            "top \(MarkdownNumber.value(thresholds.percent(for: signal.rawValue)))% of \(count) candidates "
                + "by changes in the window × cognitive complexity"

        case .safeToLeave:
            "complex, unchanged in the window, never fixed, and older than the window"

        case .testsNotKeepingUp:
            "\(minimumChanges)+ changes in the window, a test file matching by name, "
                + "and a test change in under \(Int(testChangeShare * 100))% of them"

        case .unstableFixes:
            "reverted, or fixed again within the repeat window"

        case .missingTemplate, .toolDisagreement, .uncheckedLaws, .untestedProperty:
            ""
        }
    }

    /// `candidate`'s score in `signal`, or nil when it doesn't score above
    /// zero or `signal` isn't computed from history.
    private static func score(_ signal: SignalName, _ candidate: Candidate, windowStart: String) -> Double? {
        let history = candidate.history
        let value: Double?
        switch signal {
        case .bugProne:
            value = (history.allFixes ?? 0) >= 1 ? history.fixScore : nil

        case .hotspot:
            value = Double(candidate.changes * (candidate.cognitive ?? 0))

        case .safeToLeave:
            let old = history.firstSeen.map { $0 < windowStart } ?? false
            value = candidate.changes == 0 && history.allFixes == 0 && old ? Double(candidate.cognitive ?? 0) : nil

        case .testsNotKeepingUp:
            let testChanges = history.testChanges ?? 0
            let lagging = Double(testChanges) < testChangeShare * Double(candidate.changes)
            value = history.hasTests && candidate.changes >= minimumChanges && lagging
                ? Double(candidate.changes - testChanges) : nil

        case .unstableFixes:
            value = Double((history.reverts ?? 0) + (history.repeatedFixes ?? 0))

        case .missingTemplate, .toolDisagreement, .uncheckedLaws, .untestedProperty:
            value = nil
        }
        guard let value, value > 0 else {
            return nil
        }
        return value
    }

    /// The item for `candidate`, about its family.
    private static func item(_ candidate: Candidate) -> SignalItem.Draft {
        let history = candidate.history
        return SignalItem.Draft(
            subject: history.family,
            file: history.file,
            line: history.line,
            history: SignalItem.History(
                changes: candidate.changes,
                cognitive: candidate.cognitive,
                fixes: history.fixes ?? 0,
                allFixes: history.allFixes ?? 0,
                fixScore: history.fixScore ?? 0,
                reverts: history.reverts ?? 0,
                repeatedFixes: history.repeatedFixes ?? 0,
                testChanges: history.testChanges ?? 0,
                firstSeen: history.firstSeen,
                tracedBy: history.tracedBy
            )
        )
    }
}

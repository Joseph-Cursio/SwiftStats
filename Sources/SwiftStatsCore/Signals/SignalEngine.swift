//
//  SignalEngine.swift
//  SwiftStatsCore
//
//  Computes M3's derived signals (PRD §8) from a stored snapshot's typed
//  rows. Candidates are production families outside generated files whose
//  history is known. A ranked signal keeps the top share of all candidates,
//  by nearest rank, with ties at the cut kept; the others keep every
//  family meeting their condition. Everything ranked is listed with a
//  member flag, so `top` can show a full list where membership is short.
//

import Foundation

/// Computes signals.
public enum SignalEngine {
    /// One candidate family with its inputs.
    private struct Candidate {
        let history: FamilyHistoryRow
        let cognitive: Int?
        let changes: Int
    }

    /// The fewest changes in the window for "tests not keeping up".
    static let minimumChanges = 3
    /// The share of changes with a test change below which tests aren't keeping up.
    static let testChangeShare = 0.25

    /// The signals of `snapshot`, in report order, with ranked signals'
    /// membership set by `thresholds`.
    public static func signals(of snapshot: StoredSnapshot, thresholds: SignalThresholds) -> [SignalResult] {
        guard let run = snapshot.history else {
            let reason = historyAbsence(snapshot.info)
            return SignalName.reportOrder.map { name in
                SignalResult(
                    name: name,
                    leftOut: reason,
                    rule: rule(for: name, thresholds: thresholds, count: 0),
                    candidates: 0,
                    items: []
                )
            }
        }
        let candidates = self.candidates(snapshot)
        return SignalName.reportOrder.map { name in
            let scored = candidates.compactMap { candidate in
                score(name, candidate, windowStart: run.windowStart).map { value in (candidate, value) }
            }
            let ranked = scored.sorted { lhs, rhs in
                let (left, right) = (lhs.0.history, rhs.0.history)
                return (rhs.1, left.family, left.file, left.line) < (lhs.1, right.family, right.file, right.line)
            }
            let cut = memberCount(name, ranked: ranked.map(\.1), candidates: candidates.count, thresholds: thresholds)
            let items = ranked.enumerated().map { offset, entry in
                item(entry.0, rank: offset + 1, score: entry.1, member: offset < cut)
            }
            return SignalResult(
                name: name,
                leftOut: nil,
                rule: rule(for: name, thresholds: thresholds, count: candidates.count),
                candidates: candidates.count,
                items: items
            )
        }
    }

    /// Why a snapshot has no history, from its history collector's run.
    private static func historyAbsence(_ info: SnapshotInfo) -> String {
        guard let run = info.collectors.first(where: { $0.name == HistoryCollector.name }) else {
            return "history was not collected (the snapshot predates M3)"
        }
        return "history was not collected: \(run.state.rawValue)" + (run.reason.map { ", \($0)" } ?? "")
    }

    /// Production families outside generated files with known history.
    private static func candidates(_ snapshot: StoredSnapshot) -> [Candidate] {
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

    /// `candidate`'s score in `signal`, or nil when it doesn't qualify.
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
        }
        guard let value, value > 0 else {
            return nil
        }
        return value
    }

    /// How many of `ranked` (scores, highest first) are members.
    private static func memberCount(
        _ signal: SignalName,
        ranked: [Double],
        candidates: Int,
        thresholds: SignalThresholds
    ) -> Int {
        guard signal.isRanked else {
            return ranked.count
        }
        let rankCut = Int((thresholds.percent(for: signal.rawValue) * Double(candidates) / 100).rounded(.up))
        guard rankCut > 0, ranked.isEmpty == false else {
            return 0
        }
        var count = min(rankCut, ranked.count)
        while count < ranked.count, ranked[count] == ranked[count - 1] {
            count += 1
        }
        return count
    }

    /// The membership rule as reports state it.
    private static func rule(for signal: SignalName, thresholds: SignalThresholds, count: Int) -> String {
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
        }
    }

    /// The item for `candidate`.
    private static func item(_ candidate: Candidate, rank: Int, score: Double, member: Bool) -> SignalItem {
        let history = candidate.history
        return SignalItem(
            rank: rank,
            family: history.family,
            file: history.file,
            line: history.line,
            score: score,
            member: member,
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
    }
}

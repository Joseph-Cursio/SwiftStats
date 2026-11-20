//
//  SignalEngine.swift
//  SwiftStatsCore
//
//  Computes the derived signals (PRD §8) from a snapshot's typed rows and
//  the other inputs the workspace gathers. Each signal declares the inputs
//  it needs and is left out, with the reason, when one is missing; else it
//  scores the candidates in its pool. A ranked signal lists the candidates
//  scoring above zero and keeps the top share of its pool, by nearest
//  rank, with ties at the cut kept; the others list only their members.
//  Items sort by their signal's key, by default score, highest first, then
//  subject, file and line, and are ranked by position. Everything listed
//  carries a member flag, so `top` can show a full list where membership
//  is short.
//

/// Computes signals.
public enum SignalEngine {
    /// The signals of `inputs`, in report order, with ranked signals'
    /// membership set by `thresholds`.
    public static func signals(of inputs: SignalInputs, thresholds: SignalThresholds) -> [SignalResult] {
        let snapshot = inputs.snapshot
        lazy var families = HistorySignals.pool(snapshot)
        var results: [SignalResult] = []
        for name in SignalName.reportOrder {
            let reason = leftOut(name.requirements, in: snapshot) ?? leftOut(name, comparing: inputs)
            var computation: SignalComputation?
            if reason == nil {
                switch name {
                case .bugProne, .hotspot, .safeToLeave, .testsNotKeepingUp, .unstableFixes:
                    computation = HistorySignals.compute(
                        name,
                        pool: families,
                        snapshot: snapshot,
                        thresholds: thresholds
                    )

                case .cloneHotspot:
                    computation = CloneHotspot.compute(snapshot, thresholds: thresholds)

                case .divergentClones:
                    computation = DivergentClones.compute(inputs)

                case .missingTemplate:
                    computation = MissingTemplate.compute(snapshot)

                case .toolDisagreement:
                    computation = ToolDisagreement.compute(snapshot)

                case .uncheckedLaws:
                    computation = UncheckedLaws.compute(snapshot)

                case .untestedProperty:
                    computation = UntestedProperty.compute(snapshot)
                }
            }
            guard let computation else {
                // A computation finds no input only where its requirements
                // say one is missing: history, or an earlier snapshot.
                results.append(SignalResult(
                    name: name,
                    leftOut: reason ?? historyAbsence(snapshot.info),
                    rule: rule(for: name, thresholds: thresholds),
                    candidates: 0,
                    items: []
                ))
                continue
            }
            results.append(result(name, computation, thresholds: thresholds))
        }
        return results
    }

    /// Why a signal needing `requirements` can't be computed from
    /// `snapshot`; nil when it can. A missing history says so as M3 did;
    /// else a snapshot stored before M4, or without a row for a collector
    /// or its scan facts, predates M4; else the first required collector
    /// that didn't run is named with its state and reason.
    static func leftOut(_ requirements: [SignalRequirement], in snapshot: StoredSnapshot) -> String? {
        if requirements.contains(.history), snapshot.history == nil {
            return historyAbsence(snapshot.info)
        }
        let predates = "the snapshot predates M4"
        for requirement in requirements {
            switch requirement {
            case .collector(let name):
                guard snapshot.reportSchemaVersion >= SignalRequirement.firstM4Schema,
                      let run = snapshot.info.collectors.first(where: { $0.name == name }) else {
                    return predates
                }
                guard run.state == .ran else {
                    return "needs \(name): \(run.state.rawValue)" + (run.reason.map { ", \($0)" } ?? "")
                }

            case .history:
                continue

            case .m4Snapshot:
                guard snapshot.reportSchemaVersion >= SignalRequirement.firstM4Schema, snapshot.scanFacts != nil else {
                    return predates
                }
            }
        }
        return nil
    }

    /// Why `signal`, which compares the snapshot with an earlier one, can't
    /// be: git failed, or no earlier snapshot qualifies; nil when it can,
    /// or when `signal` compares none.
    static func leftOut(_ signal: SignalName, comparing inputs: SignalInputs) -> String? {
        guard signal == .divergentClones else {
            return nil
        }
        if let failure = inputs.gitFailure {
            return failure
        }
        guard inputs.earlier == nil else {
            return nil
        }
        return inputs.earlierNote ?? DivergentClones.noEarlier
    }

    /// `computation` ranked: sorted by its keys, a ranked signal's
    /// candidates scoring zero or less dropped, and members marked.
    static func result(
        _ signal: SignalName,
        _ computation: SignalComputation,
        thresholds: SignalThresholds
    ) -> SignalResult {
        let listed = signal.isRanked ? computation.scored.filter { $0.score > 0 } : computation.scored
        let sorted = listed.sorted { $0.sortKey < $1.sortKey }
        let cut = memberCount(
            signal,
            ranked: sorted.map(\.score),
            candidates: computation.candidates,
            thresholds: thresholds
        )
        return SignalResult(
            name: signal,
            leftOut: nil,
            rule: computation.rule,
            candidates: computation.candidates,
            items: sorted.enumerated().map { offset, entry in
                SignalItem(entry.draft, rank: offset + 1, score: entry.score, member: offset < cut)
            }
        )
    }

    /// Why a snapshot has no history, from its history collector's run.
    private static func historyAbsence(_ info: SnapshotInfo) -> String {
        guard let run = info.collectors.first(where: { $0.name == HistoryCollector.name }) else {
            return "history was not collected (the snapshot predates M3)"
        }
        return "history was not collected: \(run.state.rawValue)" + (run.reason.map { ", \($0)" } ?? "")
    }

    /// The rule a left-out signal states: as over an empty pool, without
    /// the counts a computed M4 signal adds.
    private static func rule(for signal: SignalName, thresholds: SignalThresholds) -> String {
        switch signal {
        case .bugProne, .hotspot, .safeToLeave, .testsNotKeepingUp, .unstableFixes:
            HistorySignals.rule(for: signal, thresholds: thresholds, count: 0)

        case .cloneHotspot:
            CloneHotspot.rule(thresholds: thresholds, count: nil)

        case .divergentClones:
            DivergentClones.rule

        case .missingTemplate:
            MissingTemplate.rule

        case .toolDisagreement:
            ToolDisagreement.rule

        case .uncheckedLaws:
            UncheckedLaws.rule

        case .untestedProperty:
            UntestedProperty.rule
        }
    }

    /// How many of `ranked` (scores, in listed order) are members: for a
    /// ranked signal, the top share of `candidates`, extended over ties at
    /// the cut; for the others, all.
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
}

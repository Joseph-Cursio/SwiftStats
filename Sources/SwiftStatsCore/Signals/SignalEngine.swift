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
            let computed = reason == nil
                ? computation(name, inputs: inputs, thresholds: thresholds) { families }
                : nil
            guard let computed else {
                // A computation finds no input only where its requirements
                // say one is missing: history, an earlier snapshot, or the
                // coverage rows of a coverage run that ran.
                results.append(SignalResult(
                    name: name,
                    leftOut: reason ?? missingInput(name, snapshot),
                    rule: rule(for: name, thresholds: thresholds),
                    candidates: 0,
                    items: []
                ))
                continue
            }
            results.append(result(name, computed, thresholds: thresholds))
        }
        return results
    }

    /// `signal` computed from `inputs`, whose requirements hold; nil when
    /// an input its requirements don't check is missing. `families` gives
    /// the history signals' pool, worked out once for them all.
    private static func computation(
        _ signal: SignalName,
        inputs: SignalInputs,
        thresholds: SignalThresholds,
        families: () -> [HistorySignals.Candidate]
    ) -> SignalComputation? {
        let snapshot = inputs.snapshot
        switch signal {
        case .bugProne, .hotspot, .safeToLeave, .testsNotKeepingUp, .unstableFixes:
            return HistorySignals.compute(signal, pool: families(), snapshot: snapshot, thresholds: thresholds)

        case .cloneHotspot:
            return CloneHotspot.compute(snapshot, thresholds: thresholds)

        case .divergentClones:
            return DivergentClones.compute(inputs)

        case .bestPropertyTarget, .genuinelyUnderTested, .unevenCloneMutation, .weakTests:
            return mutationComputation(signal, snapshot: snapshot, thresholds: thresholds)

        case .missingTemplate:
            return MissingTemplate.compute(snapshot)

        case .riskyUntested:
            return RiskyUntested.compute(snapshot)

        case .toolDisagreement:
            return ToolDisagreement.compute(snapshot)

        case .uncheckedLaws:
            return UncheckedLaws.compute(snapshot)

        case .unevenCloneTesting:
            return UnevenCloneTesting.compute(snapshot)

        case .untestedProperty:
            return UntestedProperty.compute(snapshot)
        }
    }

    /// Why a signal needing `requirements` can't be computed from
    /// `snapshot`; nil when it can. A missing history says so as M3 did;
    /// else, in the requirements' order, a snapshot stored before M6, or
    /// without a SwiftMutator run, predates M6; one stored before M5, or
    /// without a coverage run, predates M5; one stored before M4, or
    /// without a row for a collector or its scan facts, predates M4; the
    /// first required collector that didn't run is named with its state
    /// and reason; and mutation results that don't list code no test ran
    /// say so.
    static func leftOut(_ requirements: [SignalRequirement], in snapshot: StoredSnapshot) -> String? {
        if requirements.contains(.history), snapshot.history == nil {
            return historyAbsence(snapshot.info)
        }
        for requirement in requirements {
            switch requirement {
            case .collector(let name):
                guard snapshot.reportSchemaVersion >= SignalRequirement.firstM4Schema,
                      let run = snapshot.info.collectors.first(where: { $0.name == name }) else {
                    return "the snapshot predates M4"
                }
                guard run.state == .ran else {
                    return "needs \(name): \(run.state.rawValue)" + (run.reason.map { ", \($0)" } ?? "")
                }

            case .history:
                continue

            case .m4Snapshot, .m5Snapshot, .m6Snapshot, .notCoveredListed:
                if let reason = rowsMissing(requirement, in: snapshot) {
                    return reason
                }
            }
        }
        return nil
    }

    /// Why `snapshot` lacks the rows `requirement` asks for: stored before
    /// the milestone that added them, without the collector run that
    /// marks them, or, for listed code no test ran, results that don't
    /// list it; nil when it has them, and for any other requirement.
    private static func rowsMissing(_ requirement: SignalRequirement, in snapshot: StoredSnapshot) -> String? {
        let schema = snapshot.reportSchemaVersion
        let collectors = Set(snapshot.info.collectors.map(\.name))
        switch requirement {
        case .m4Snapshot:
            return schema >= SignalRequirement.firstM4Schema && snapshot.scanFacts != nil
                ? nil : "the snapshot predates M4"

        case .m5Snapshot:
            return schema >= SignalRequirement.firstM5Schema && collectors.contains(CoverageAdapter.name)
                ? nil : "the snapshot predates M5"

        case .m6Snapshot:
            return schema >= SignalRequirement.firstM6Schema && collectors.contains(MutationAdapter.name)
                ? nil : "the snapshot predates M6"

        case .notCoveredListed:
            guard let mutation = snapshot.mutation?.report, mutation.listsNotCovered == false else {
                return nil
            }
            return GenuinelyUnderTested.notListedReason(of: mutation)

        case .collector, .history:
            return nil
        }
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

    /// M6's signal `signal`, weak tests, genuinely under-tested, best
    /// property-test target or uneven clone testing's mutation part,
    /// computed from `snapshot`.
    private static func mutationComputation(
        _ signal: SignalName,
        snapshot: StoredSnapshot,
        thresholds: SignalThresholds
    ) -> SignalComputation? {
        switch signal {
        case .weakTests:
            WeakTests.compute(snapshot, thresholds: thresholds)

        case .genuinelyUnderTested:
            GenuinelyUnderTested.compute(snapshot, thresholds: thresholds)

        case .unevenCloneMutation:
            UnevenCloneMutation.compute(snapshot, thresholds: thresholds)

        default:
            BestPropertyTarget.compute(snapshot)
        }
    }

    /// The rule M6's signal `signal` states when left out.
    private static func mutationRule(_ signal: SignalName, thresholds: SignalThresholds) -> String {
        switch signal {
        case .weakTests:
            WeakTests.rule(thresholds: thresholds)

        case .genuinelyUnderTested:
            GenuinelyUnderTested.rule(thresholds: thresholds)

        case .unevenCloneMutation:
            UnevenCloneMutation.rule(thresholds: thresholds)

        default:
            BestPropertyTarget.rule
        }
    }

    /// Why `signal`'s computation found no input its requirements check:
    /// for a mutation signal, the mutation rows a run that ran leaves,
    /// then, for one needing coverage, the coverage rows; for a coverage
    /// signal, the coverage rows; for the others, history.
    private static func missingInput(_ signal: SignalName, _ snapshot: StoredSnapshot) -> String {
        let noCoverage = "the snapshot holds no coverage rows"
        if signal.requirements.contains(.m6Snapshot) {
            return snapshot.mutation == nil ? "the snapshot holds no mutation rows" : noCoverage
        }
        guard signal.requirements.contains(.m5Snapshot) else {
            return historyAbsence(snapshot.info)
        }
        return noCoverage
    }

    /// Why a snapshot has no history, from its history collector's run.
    private static func historyAbsence(_ info: SnapshotInfo) -> String {
        guard let run = info.collectors.first(where: { $0.name == HistoryCollector.name }) else {
            return "history was not collected (the snapshot predates M3)"
        }
        return "history was not collected: \(run.state.rawValue)" + (run.reason.map { ", \($0)" } ?? "")
    }

    /// The rule a left-out signal states: as over an empty pool, without
    /// the counts a computed M4 signal adds; an M6 signal's with the
    /// thresholds it would use.
    private static func rule(for signal: SignalName, thresholds: SignalThresholds) -> String {
        switch signal {
        case .bugProne, .hotspot, .safeToLeave, .testsNotKeepingUp, .unstableFixes:
            HistorySignals.rule(for: signal, thresholds: thresholds, count: 0)

        case .cloneHotspot:
            CloneHotspot.rule(thresholds: thresholds, count: nil)

        case .divergentClones:
            DivergentClones.rule

        case .bestPropertyTarget, .genuinelyUnderTested, .unevenCloneMutation, .weakTests:
            mutationRule(signal, thresholds: thresholds)

        case .missingTemplate:
            MissingTemplate.rule

        case .riskyUntested:
            RiskyUntested.rule

        case .toolDisagreement:
            ToolDisagreement.rule

        case .uncheckedLaws:
            UncheckedLaws.rule

        case .unevenCloneTesting:
            UnevenCloneTesting.rule

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

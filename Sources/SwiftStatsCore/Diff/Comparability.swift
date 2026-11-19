//
//  Comparability.swift
//  SwiftStatsCore
//
//  Which collectors' results two snapshots can compare (PRD §6.6).
//

/// Decides each collector's comparability.
enum Comparability {
    /// Each collector in either snapshot, sorted by name.
    static func compare(_ old: SnapshotInfo, _ new: SnapshotInfo) -> [CollectorComparison] {
        let oldRuns = Dictionary(old.collectors.map { ($0.name, $0) }) { first, _ in first }
        let newRuns = Dictionary(new.collectors.map { ($0.name, $0) }) { first, _ in first }
        let names = Set(oldRuns.keys).union(newRuns.keys).sorted()
        let ownOutcome = outcome(oldRuns[SwiftStatsCollector.name], newRuns[SwiftStatsCollector.name])
        return names.map { name in
            var result = outcome(oldRuns[name], newRuns[name])
            if name == DependencyGraphAdapter.name, result.outcome == .compared, ownOutcome.outcome != .compared {
                result = (.notComparable, "SwiftStats' build differs, and its own code reads the graph")
            }
            if name == HistoryCollector.name, result.outcome == .compared, ownOutcome.outcome != .compared {
                result = (.notComparable, "SwiftStats' build differs, and its own code reads the history")
            }
            return CollectorComparison(name: name, outcome: result.outcome, reason: result.reason)
        }
    }

    /// Whether two runs of one collector compare, and why not.
    private static func outcome(
        _ old: CollectorRunInfo?,
        _ new: CollectorRunInfo?
    ) -> (outcome: ComparisonOutcome, reason: String?) {
        guard let old, let new, old.state == .ran, new.state == .ran else {
            let reasons = [describe(old, side: "older"), describe(new, side: "newer")].compactMap(\.self)
            return (.notCollected, reasons.joined(separator: "; "))
        }
        guard let oldIdentity = old.identity, let newIdentity = new.identity else {
            return (.notComparable, "a build identity is unknown")
        }
        if oldIdentity != newIdentity {
            return (.notComparable, "different builds")
        }
        if old.version != new.version {
            return (.notComparable, "different versions")
        }
        if old.options != new.options {
            return (.notComparable, "different options")
        }
        return (.compared, nil)
    }

    /// Why `run` gave nothing on `side`, or nil when it ran.
    private static func describe(_ run: CollectorRunInfo?, side: String) -> String? {
        guard let run else {
            return "not in the \(side) snapshot"
        }
        guard run.state != .ran else {
            return nil
        }
        return "\(run.state.rawValue) in the \(side) snapshot" + (run.reason.map { ": \($0)" } ?? "")
    }
}

//
//  Comparability.swift
//  SwiftStatsCore
//
//  Which collectors' results two snapshots can compare (PRD §6.6): those
//  SwiftStats' own code reads or maps also need SwiftStats' build to
//  match, and the index and the dead code (M7) need the T1 build's too.
//

/// Decides each collector's comparability.
enum Comparability {
    /// Collectors whose results SwiftStats' own code reads or maps, so they
    /// compare only when `swiftstats` does, with the reason they don't.
    private static let needingOwnBuild = [
        BuildAdapter.name: "SwiftStats' build differs, and its own code maps the timings and warnings",
        CoverageAdapter.name: "SwiftStats' build differs, and its own code maps the coverage",
        DependencyGraphAdapter.name: "SwiftStats' build differs, and its own code reads the graph",
        HistoryCollector.name: "SwiftStats' build differs, and its own code reads the history",
        EffectCollector.name: "SwiftStats' build differs, and its own code maps the side effects",
        IndexAdapter.name: "SwiftStats' build differs, and its own code reads the index",
        MutationAdapter.name: "SwiftStats' build differs, and its own code maps the mutants",
        PeripheryAdapter.name: "SwiftStats' build differs, and its own code maps the dead code"
    ]
    /// Collectors whose results come from the T1 build's output, so they
    /// compare only when `build` does too.
    private static let needingBuild: Set<String> = [IndexAdapter.name, PeripheryAdapter.name]
    /// Why a collector of `needingBuild` doesn't compare when `build`
    /// doesn't.
    private static let buildDiffers = "the build differs: the index and the dead code come from it"

    /// Each collector in either snapshot, sorted by name.
    static func compare(_ old: SnapshotInfo, _ new: SnapshotInfo) -> [CollectorComparison] {
        let oldRuns = Dictionary(old.collectors.map { ($0.name, $0) }) { first, _ in first }
        let newRuns = Dictionary(new.collectors.map { ($0.name, $0) }) { first, _ in first }
        let names = Set(oldRuns.keys).union(newRuns.keys).sorted()
        let ownOutcome = outcome(oldRuns[SwiftStatsCollector.name], newRuns[SwiftStatsCollector.name])
        // One collector's outcome, given SwiftStats' own.
        func compared(_ name: String) -> (outcome: ComparisonOutcome, reason: String?) {
            let result = outcome(oldRuns[name], newRuns[name])
            if let reason = needingOwnBuild[name], result.outcome == .compared, ownOutcome.outcome != .compared {
                return (.notComparable, reason)
            }
            return result
        }
        let buildOutcome = compared(BuildAdapter.name)
        return names.map { name in
            var result = compared(name)
            if needingBuild.contains(name), result.outcome == .compared, buildOutcome.outcome != .compared {
                result = (.notComparable, buildDiffers)
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

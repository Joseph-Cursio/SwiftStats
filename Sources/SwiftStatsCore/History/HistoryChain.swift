//
//  HistoryChain.swift
//  SwiftStatsCore
//
//  Traces each family back from the analysed commit (PRD §7.13). Lineages
//  start from the families of the analysed commit's own files, parsed as
//  every past version is, so their keys agree with the events by
//  construction; the scan's families are then joined to them, which on a
//  dirty tree matches uncommitted renames as `diff` would. A scan family
//  with no committed counterpart has no history, not an empty one.
//

/// The lineages of a scan's families.
struct HistoryChain {
    /// Every lineage.
    private(set) var lineages: [Lineage] = []
    /// Each scan family with its lineage, or nil when it has none.
    private(set) var families: [(family: FunctionFamily, lineage: Int?)] = []
    /// Problems worth reporting.
    private(set) var warnings: [String] = []

    /// Traces `seeds` (the analysed commit's families) back through
    /// `events` (each commit's, newest first) and joins `scan` to them.
    init(seeds: [FunctionFamily], scan: [FunctionFamily], events: [[HistoryEvent]]) {
        var tracked: [FamilyRef: Int] = [:]
        for seed in seeds {
            let ref = FamilyRef(seed)
            guard tracked[ref] == nil else {
                continue
            }
            tracked[ref] = lineages.count
            lineages.append(Lineage())
        }
        let seedLineage = tracked
        for (index, commitEvents) in events.enumerated() {
            var moving: [(event: HistoryEvent, lineage: Int)] = []
            for event in commitEvents {
                if let new = event.new, let lineage = tracked.removeValue(forKey: new) {
                    moving.append((event, lineage))
                }
            }
            for (event, lineage) in moving {
                if event.changed {
                    lineages[lineage].changes.append(index)
                }
                lineages[lineage].link(event.method)
                if let old = event.old, tracked[old] == nil {
                    tracked[old] = lineage
                } else {
                    lineages[lineage].birth = index
                }
            }
        }
        let unborn = seedLineage.values.filter { lineages[$0].birth == nil }.count
        if unborn > 0 {
            warnings.append(
                "\(unborn) families go back further than the history read, so their first-seen dates are unknown"
            )
        }
        join(scan: scan, seeds: seeds, seedLineage: seedLineage)
    }

    /// Joins each scan family to a seed's lineage: by key and file, then by
    /// diff's matching for what is left.
    private mutating func join(scan: [FunctionFamily], seeds: [FunctionFamily], seedLineage: [FamilyRef: Int]) {
        var joined: [FamilyRef: Int] = [:]
        var leftScan: [FunctionFamily] = []
        var usedSeeds: Set<FamilyRef> = []
        for family in scan {
            let ref = FamilyRef(family)
            if let lineage = seedLineage[ref], usedSeeds.insert(ref).inserted {
                joined[ref] = lineage
            } else {
                leftScan.append(family)
            }
        }
        let leftSeeds = seeds.filter { usedSeeds.contains(FamilyRef($0)) == false }
        if leftScan.isEmpty == false, leftSeeds.isEmpty == false {
            for match in FamilyMatcher.match(old: leftSeeds, new: leftScan).matches {
                guard let lineage = seedLineage[FamilyRef(match.old)] else {
                    continue
                }
                joined[FamilyRef(match.new)] = lineage
                lineages[lineage].link(match.method)
            }
        }
        families = scan.map { ($0, joined[FamilyRef($0)]) }
    }
}

//
//  SnapshotDiff.swift
//  SwiftStatsCore
//
//  Compares two stored snapshots (PRD §6.6): which collectors compare, which
//  function families were added, removed, moved, renamed or changed, which
//  metrics moved, and which test bundles came or went (M5).
//

/// Diffs two snapshots.
public enum SnapshotDiff {
    /// What changed from `old` to `new`.
    public static func diff(_ old: StoredSnapshot, _ new: StoredSnapshot) -> SnapshotDiffReport {
        let collectors = Comparability.compare(old.info, new.info)
        let compared = Set(collectors.filter { $0.outcome == .compared }.map(\.name))
        var families: [FamilyChange] = []
        var functions: [FunctionDelta] = []
        var warnings: [String] = []
        if compared.contains(SwiftStatsCollector.name) {
            let result = FamilyMatcher.match(
                old: FunctionFamily.families(old.functions),
                new: FunctionFamily.families(new.functions)
            )
            warnings = result.warnings
            families += result.removed.map { unmatched($0, status: .removed) }
            families += result.added.map { unmatched($0, status: .added) }
            let counts = FindingCounts(old: old.findings, new: new.findings, tools: compared)
            let coverage = CoverageMetrics(old: old.coverage, new: new.coverage, compared: compared)
            for match in result.matches {
                let members = MemberPairing.pair(match.old, match.new)
                if let change = change(match, members: members) {
                    families.append(change)
                }
                functions += members.pairs.compactMap { pair in
                    FunctionMetrics.delta(pair.0, pair.1, counts: counts, coverage: coverage)
                }
            }
        }
        return SnapshotDiffReport(
            schemaVersion: SnapshotDiffReport.currentSchemaVersion,
            older: DiffSide(old.info),
            newer: DiffSide(new.info),
            collectors: collectors,
            families: families.sorted { ($0.key, $0.oldKey ?? "") < ($1.key, $1.oldKey ?? "") },
            functions: functions.sorted { $0.key < $1.key },
            rollups: rollupDeltas(old.rollups, new.rollups, compared: compared),
            bundles: CoverageBundleChange(old: old.coverage, new: new.coverage),
            warnings: warnings.sorted()
        )
    }

    /// The change for a family only in one snapshot.
    static func unmatched(_ family: FunctionFamily, status: FamilyStatus) -> FamilyChange {
        FamilyChange(
            key: family.id,
            statuses: [status],
            oldKey: status == .removed ? family.id : nil,
            oldFile: status == .removed ? family.file : nil,
            newFile: status == .added ? family.file : nil,
            matchedBy: nil,
            records: family.members.map(\.key),
            changedRecords: []
        )
    }

    /// The change for a matched family, or nil when nothing about it changed.
    static func change(
        _ match: FamilyMatcher.Match,
        members: Pairing<FunctionRow>
    ) -> FamilyChange? {
        let (old, new) = (match.old, match.new)
        let changedRecords = members.pairs.filter { $0.0.bodyHash != $0.1.bodyHash }.map(\.1.key)
            + members.unmatchedNew.map(\.key) + members.unmatchedOld.map(\.key)
        var statuses: Set<FamilyStatus> = []
        if old.file != new.file {
            statuses.insert(.moved)
        }
        if KeyForm.withoutFile(old.id, file: old.file) != KeyForm.withoutFile(new.id, file: new.file) {
            statuses.insert(.renamed)
        }
        if KeyForm.hasFileSegment(old.id, file: old.file) != KeyForm.hasFileSegment(new.id, file: new.file) {
            statuses.insert(.accessChanged)
        }
        if changedRecords.isEmpty == false {
            statuses.insert(.changed)
        }
        guard statuses.isEmpty == false else {
            return nil
        }
        return FamilyChange(
            key: new.id,
            statuses: statuses.sorted(),
            oldKey: old.id,
            oldFile: old.file,
            newFile: new.file,
            matchedBy: match.method,
            records: new.members.map(\.key),
            changedRecords: changedRecords.sorted()
        )
    }

    /// Roll-up numbers that differ, where their collector compares and
    /// SwiftStats does too: every roll-up counts only the files SwiftStats
    /// scanned, in the module and project part it assigned them to.
    private static func rollupDeltas(
        _ old: [RollupMetricRow],
        _ new: [RollupMetricRow],
        compared: Set<String>
    ) -> [RollupDelta] {
        guard compared.contains(SwiftStatsCollector.name) else {
            return []
        }
        let identify: (RollupMetricRow) -> String = { "\($0.scope.rawValue)\u{0}\($0.name)\u{0}\($0.metric)" }
        let oldRows = Dictionary(old.map { (identify($0), $0) }) { first, _ in first }
        let newRows = Dictionary(new.map { (identify($0), $0) }) { first, _ in first }
        return Set(oldRows.keys).union(newRows.keys).sorted().compactMap { identity in
            guard let row = newRows[identity] ?? oldRows[identity], compared.contains(row.collector) else {
                return nil
            }
            let before = CountedMetrics.value(oldRows[identity]?.value, metric: row.metric)
            let after = CountedMetrics.value(newRows[identity]?.value, metric: row.metric)
            guard before != after else {
                return nil
            }
            return RollupDelta(
                scope: row.scope,
                name: row.name,
                collector: row.collector,
                delta: MetricDelta(metric: row.metric, before: before, after: after)
            )
        }
    }
}

//
//  SnapshotDiff.swift
//  SwiftStatsCore
//
//  Compares two stored snapshots (PRD §6.6): which collectors compare, which
//  function families were added, removed, moved, renamed or changed, which
//  metrics moved, which test bundles came or went (M5), where each side's
//  mutation results came from (M6), and, when the index compares, which
//  families matched by USR and which records kept their key but not their
//  USR (M7, design §10.3). A side whose mutation results
//  leave files out (`MutationGaps`) has its mutation counts above records
//  left out of the roll-up deltas, with a warning saying so.
//

/// Diffs two snapshots.
public enum SnapshotDiff {
    /// Roll-up numbers that are facts of where results came from rather
    /// than measurements: how many mutants were carried, which each side's
    /// mutation provenance lists (M6).
    private static let provenanceMetrics: Set = ["mutation.carried"]

    /// What changed from `old` to `new`.
    public static func diff(_ old: StoredSnapshot, _ new: StoredSnapshot) -> SnapshotDiffReport {
        let collectors = Comparability.compare(old.info, new.info)
        let compared = Set(collectors.filter { $0.outcome == .compared }.map(\.name))
        var families: [FamilyChange] = []
        var functions: [FunctionDelta] = []
        var warnings: [String] = []
        let gaps = mutationGaps(old.mutation, new.mutation, compared: compared)
        if compared.contains(SwiftStatsCollector.name) {
            let usrs = IndexFacts(old: old.index, new: new.index, compared: compared)
            let result = FamilyMatcher.match(
                old: FunctionFamily.families(old.functions),
                new: FunctionFamily.families(new.functions),
                usrs: usrs
            )
            warnings = result.warnings
            families += result.removed.map { unmatched($0, status: .removed) }
            families += result.added.map { unmatched($0, status: .added) }
            let counts = FindingCounts(old: old.findings, new: new.findings, tools: compared)
            let coverage = CoverageMetrics(old: old.coverage, new: new.coverage, compared: compared)
            let mutation = MutationMetrics(old: old.mutation, new: new.mutation, compared: compared)
            for match in result.matches {
                let members = MemberPairing.pair(match.old, match.new)
                if let change = change(match, members: members, usrs: usrs) {
                    families.append(change)
                }
                functions += members.pairs.compactMap { pair in
                    FunctionMetrics.delta(pair.0, pair.1, counts: counts, coverage: coverage, mutation: mutation)
                }
            }
        }
        return SnapshotDiffReport(
            schemaVersion: SnapshotDiffReport.currentSchemaVersion,
            older: DiffSide(old.info, mutation: old.mutation),
            newer: DiffSide(new.info, mutation: new.mutation),
            collectors: collectors,
            families: families.sorted { ($0.key, $0.oldKey ?? "") < ($1.key, $1.oldKey ?? "") },
            functions: functions.sorted { $0.key < $1.key },
            rollups: rollupDeltas(old.rollups, new.rollups, compared: compared, leavingOutMutationCounts: gaps != nil),
            bundles: CoverageBundleChange(old: old.coverage, new: new.coverage),
            warnings: (warnings + [gaps].compactMap(\.self)).sorted()
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
            changedRecords: [],
            usrChanges: []
        )
    }

    /// The change for a matched family, its records paired as `members`,
    /// with no USRs to compare; nil when nothing about it changed.
    static func change(_ match: FamilyMatcher.Match, members: Pairing<FunctionRow>) -> FamilyChange? {
        change(match, members: members, usrs: .empty)
    }

    /// The change for a matched family, its records paired as `members`,
    /// with the records whose USR in `usrs` changed under the same key; nil
    /// when nothing about it changed.
    static func change(
        _ match: FamilyMatcher.Match,
        members: Pairing<FunctionRow>,
        usrs: IndexFacts
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
        let usrChanges = usrs.changes(members.pairs)
        if usrChanges.isEmpty == false {
            statuses.insert(.usrChanged)
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
            changedRecords: changedRecords.sorted(),
            usrChanges: usrChanges
        )
    }

    /// The warning that the mutation counts above records aren't compared,
    /// since `old`'s or `new`'s results leave files out; nil when neither
    /// does, or SwiftMutator's results or SwiftStats' own don't compare
    /// (`compared`), so there are no mutation roll-up deltas anyway.
    private static func mutationGaps(
        _ old: StoredMutation?,
        _ new: StoredMutation?,
        compared: Set<String>
    ) -> String? {
        guard compared.contains(MutationAdapter.name), compared.contains(SwiftStatsCollector.name) else {
            return nil
        }
        let sides = [("older", old), ("newer", new)].compactMap { side, mutation in
            mutation.flatMap { MutationGaps($0.report) }.map { "the \(side) snapshot (\($0.description))" }
        }
        guard sides.isEmpty == false else {
            return nil
        }
        return "\(MutationAdapter.name): mutation counts above records aren't compared, since files' mutants are "
            + "missing from the results of " + sides.joined(separator: " and ") + "; scores still are"
    }

    /// Roll-up numbers that differ, where their collector compares and
    /// SwiftStats does too: every roll-up counts only the files SwiftStats
    /// scanned, in the module and project part it assigned them to.
    /// Provenance numbers are left out: they never make a diff non-empty.
    /// So are the mutation counts when a side's results leave files out
    /// (`mutationGaps`): they would fall by mutants no run looked at.
    private static func rollupDeltas(
        _ old: [RollupMetricRow],
        _ new: [RollupMetricRow],
        compared: Set<String>,
        leavingOutMutationCounts: Bool
    ) -> [RollupDelta] {
        guard compared.contains(SwiftStatsCollector.name) else {
            return []
        }
        let identify: (RollupMetricRow) -> String = { "\($0.scope.rawValue)\u{0}\($0.name)\u{0}\($0.metric)" }
        let oldRows = Dictionary(old.map { (identify($0), $0) }) { first, _ in first }
        let newRows = Dictionary(new.map { (identify($0), $0) }) { first, _ in first }
        return Set(oldRows.keys).union(newRows.keys).sorted().compactMap { identity in
            guard let row = newRows[identity] ?? oldRows[identity], compared.contains(row.collector),
                  provenanceMetrics.contains(row.metric) == false,
                  leavingOutMutationCounts == false || MutationGaps.affects(row.metric) == false
            else {
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

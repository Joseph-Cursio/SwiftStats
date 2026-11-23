//
//  CoverageCarry.swift
//  SwiftStatsCore
//
//  Keeping coverage across a rescan that didn't run the coverage collector,
//  or whose run failed (M5, design §6). No T0 command can collect coverage again, so a rescan
//  of a snapshot holding it carries it when the coverage still describes
//  the scan: both scans saw a commit (never outside git or before the first
//  commit) and the same tree (both clean, or both dirty with the same hash
//  of the changes), the coverage was mapped by the rule this build maps by
//  and its public functions linked to tests by the rule this build links
//  by, and its records are exactly the new scan's production records, each
//  over the same lines. A carried run keeps the original's identity,
//  version, options and duration, and says when its coverage was collected;
//  the roll-ups are rebuilt from it as a scan builds them, and the warnings
//  mapping it gave come with it, so the report is the one the collecting
//  scan gave. A rescan whose run was asked for and failed or was skipped
//  (no `swift`, a bad `collectors.coverage.path`, coverage disabled) says
//  so in a warning. Otherwise the rescan is refused, saying why, and why
//  the run asked for didn't collect coverage.
//

/// Decides whether stored coverage carries onto a rescan, and carries it.
enum CoverageCarry {
    /// The start of a carried run's reason, before the collection date.
    static let carriedPrefix = CollectorRunInfo.carriedPrefix

    /// Skip reasons a coverage run gives when it wasn't asked for: a plain
    /// scan's, and a backfill's without tools.
    private static let unaskedSkips: Set<String> = [
        CoverageAdapter.notRequestedReason, SnapshotWorkspace.backfillToolSkipReason
    ]
    /// What says what became of a scan's own run, before `failed` or `was
    /// skipped`.
    static let ownRunLead = "this scan's coverage run "

    /// Why `held` can't be carried onto `snapshot`, a scan of the same
    /// package, commit and dirtiness whose coverage collector didn't run;
    /// nil when it can.
    static func refusal(of held: HeldCoverage, onto snapshot: ScannedSnapshot) -> String? {
        refusal(of: held, git: snapshot.info.git, records: snapshot.report.records)
    }

    /// Why `held` can't be carried onto a scan at `git` whose records are
    /// `records`; nil when it can.
    static func refusal(of held: HeldCoverage, git: GitState, records: [FunctionRecord]) -> String? {
        stateRefusal(of: held, git: git) ?? recordsRefusal(of: held, onto: records)
    }

    /// Why `held` can't be carried onto any scan at `git` by this build,
    /// whatever its records: the reasons known before a scan runs; nil
    /// when there is none.
    static func stateRefusal(of held: HeldCoverage, git: GitState) -> String? {
        guard held.git.commit != nil, git.commit != nil else {
            return "no git commit to compare against"
        }
        guard held.git.isDirty == git.isDirty, held.git.dirtyHash == git.dirtyHash else {
            return "the uncommitted changes differ"
        }
        guard held.run.options.contains("map: " + CoverageMapper.rule) else {
            return "it was mapped by another rule"
        }
        // The stored links to tests come with the coverage.
        guard held.run.options.contains("links: " + CoverageTestLinks.rule) else {
            return "its functions were linked to tests by another rule"
        }
        return nil
    }

    /// Why `held`'s records aren't the production records among `records`,
    /// each over the lines it spanned, naming the first key that differs;
    /// nil when they are.
    private static func recordsRefusal(of held: HeldCoverage, onto records: [FunctionRecord]) -> String? {
        let production = Dictionary(
            records.filter { $0.role == .production }.map { record in
                let lines = (start: record.range.start.line, end: record.range.end.line)
                return (record.key, HeldCoverage.Span(file: record.file, startLine: lines.start, endLine: lines.end))
            }
        ) { first, _ in first }
        let stored = Set(held.coverage.report.records.map(\.key))
        for key in stored.sorted() {
            guard let span = production[key] else {
                return "`\(key)` names no record now"
            }
            guard held.spans[key] == span else {
                return "`\(key)` spans other lines now"
            }
        }
        if let added = production.keys.filter({ stored.contains($0) == false }).min() {
            return "`\(added)` has no coverage"
        }
        return nil
    }

    /// What became of `snapshot`'s own coverage run when it was asked for
    /// and didn't run: "this scan's coverage run failed (…)" or "was
    /// skipped (…)", with its reason; nil when it ran, wasn't asked for, or
    /// isn't there.
    static func ownRun(of snapshot: ScannedSnapshot) -> String? {
        guard let run = snapshot.info.collectors.first(where: { $0.name == CoverageAdapter.name }) else {
            return nil
        }
        return ownRun(state: run.state, reason: run.reason)
    }

    /// What became of a coverage run that ended as `state` for `reason`,
    /// as `ownRun(of:)` says it.
    static func ownRun(state: CollectorState, reason given: String?) -> String? {
        let reason = given ?? "no reason given"
        switch state {
        case .ran:
            return nil

        case .failed:
            return "\(ownRunLead)failed (\(reason))"

        case .skipped:
            return unaskedSkips.contains(reason) ? nil : "\(ownRunLead)was skipped (\(reason))"
        }
    }

    /// `snapshot` with `held`'s coverage and its warnings attached, its
    /// coverage run the original's with a reason saying when the coverage
    /// was collected, and the roll-ups' coverage rebuilt; when `snapshot`'s
    /// own coverage run was asked for and failed or was skipped, a warning
    /// says so, which a later carry doesn't repeat.
    static func carried(_ held: HeldCoverage, onto snapshot: ScannedSnapshot) -> ScannedSnapshot {
        let notice = ownRun(of: snapshot).map { what in
            ScanWarning(
                file: nil,
                message: "coverage: \(what), so it keeps the coverage collected \(held.coverage.collectedAt)"
            )
        }
        let run = held.run.carried(collectedAt: held.coverage.collectedAt)
        return ScannedSnapshot(
            info: snapshot.info.with(run: run),
            report: snapshot.report.with(
                coverage: held.coverage.report,
                status: run.status,
                warnings: held.warnings + [notice].compactMap(\.self)
            )
        )
    }
}

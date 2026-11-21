//
//  CoverageCarry.swift
//  SwiftStatsCore
//
//  Keeping coverage across a rescan that didn't run the coverage collector,
//  or whose run failed (M5, design §6). No T0 command can collect coverage again, so a rescan
//  of a snapshot holding it carries it when the coverage still describes
//  the scan: both scans saw a commit (never outside git or before the first
//  commit) and the same tree (both clean, or both dirty with the same hash
//  of the changes), the coverage was mapped by the rule this build maps by,
//  and its records are exactly the new scan's production records, each
//  over the same lines. A carried run keeps the original's identity,
//  version, options and duration, and says when its coverage was collected;
//  the roll-ups are rebuilt from it as a scan builds them, and the warnings
//  mapping it gave come with it, so the report is the one the collecting
//  scan gave. A rescan whose run failed says so in a warning. Otherwise the
//  rescan is refused, saying why.
//

/// Decides whether stored coverage carries onto a rescan, and carries it.
enum CoverageCarry {
    /// The start of a carried run's reason, before the collection date.
    static let carriedPrefix = "carried from the scan of "

    /// Why `held` can't be carried onto `snapshot`, a scan of the same
    /// package, commit and dirtiness whose coverage collector didn't run;
    /// nil when it can.
    static func refusal(of held: HeldCoverage, onto snapshot: ScannedSnapshot) -> String? {
        let git = snapshot.info.git
        guard held.git.commit != nil, git.commit != nil else {
            return "no git commit to compare against"
        }
        guard held.git.isDirty == git.isDirty, held.git.dirtyHash == git.dirtyHash else {
            return "the uncommitted changes differ"
        }
        guard held.run.options.contains("map: " + CoverageMapper.rule) else {
            return "it was mapped by another rule"
        }
        return recordsRefusal(of: held, onto: snapshot.report.records)
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

    /// `snapshot` with `held`'s coverage and its warnings attached, its
    /// coverage run the original's with a reason saying when the coverage
    /// was collected, and the roll-ups' coverage rebuilt; when `snapshot`'s
    /// own coverage run failed, a warning says so.
    static func carried(_ held: HeldCoverage, onto snapshot: ScannedSnapshot) -> ScannedSnapshot {
        let failed = snapshot.info.collectors.first { $0.name == CoverageAdapter.name && $0.state == .failed }
        let failure = failed.map { run in
            ScanWarning(
                file: nil,
                message: "coverage: this scan's coverage run failed (\(run.reason ?? "no reason given")), "
                    + "so it keeps the coverage collected \(held.coverage.collectedAt)"
            )
        }
        let original = held.run
        let run = CollectorRunInfo(
            name: original.name,
            state: .ran,
            reason: reason(of: original, collectedAt: held.coverage.collectedAt),
            version: original.version,
            identity: original.identity,
            identityLabel: original.identityLabel,
            options: original.options,
            durationMilliseconds: original.durationMilliseconds
        )
        let status = CollectorStatus(
            name: run.name,
            state: run.state,
            version: run.version,
            reason: run.reason,
            options: run.options
        )
        return ScannedSnapshot(
            info: snapshot.info.with(run: run),
            report: snapshot.report.with(
                coverage: held.coverage.report,
                status: status,
                warnings: held.warnings + [failure].compactMap(\.self)
            )
        )
    }

    /// A carried run's reason: when its coverage was collected, then the
    /// reason the run that collected it gave (failing tests), which a run
    /// carried before still holds after its own date.
    private static func reason(of run: CollectorRunInfo, collectedAt: String) -> String {
        let carried = carriedPrefix + collectedAt
        let separator = "; "
        var original = run.reason
        if let reason = original, reason.hasPrefix(carried) {
            let rest = reason.dropFirst(carried.count)
            original = rest.hasPrefix(separator) ? String(rest.dropFirst(separator.count)) : nil
        }
        return original.map { carried + separator + $0 } ?? carried
    }
}

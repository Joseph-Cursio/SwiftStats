//
//  MutationCarry.swift
//  SwiftStatsCore
//
//  Keeping mutation results across a rescan that didn't run the SwiftMutator
//  collector, or whose run failed (M6, design §6.4), as `CoverageCarry`
//  keeps coverage: only `scan --mutation` collects them, so a rescan of a
//  snapshot holding them carries them when they still describe the scan:
//  both scans saw a commit and the same tree (both clean, or both dirty
//  with the same hash of the changes), the results were mapped by the rule
//  this build maps by, every record a stored mutant names is a production
//  record of the scan in the same file over the same lines, every
//  production record of the scan was one of the held scan's (M5's added-
//  record check), every scanned file holding mapped mutants has the bytes
//  they were tested on, and no mutant left unmapped because its file
//  wasn't parsed lies in a file the scan now parses.
//  A carried result keeps the original runs, identity, version, options and
//  duration, state `ran`, a reason saying when the results were collected,
//  each mutant's own `carried` flag and the warnings describing it; the
//  roll-ups are rebuilt from it as a scan builds them. A rescan whose run
//  was asked for and failed or was skipped says so in a warning. Otherwise
//  the rescan is refused, saying why, and why the run asked for didn't
//  collect results. No new collector state: cross-commit provenance lives
//  on each mutant row (U6).
//

/// Decides whether stored mutation results carry onto a rescan, and carries
/// them.
enum MutationCarry {
    /// Skip reasons a SwiftMutator run gives when it wasn't asked for: a
    /// plain scan's, and a backfill's without tools.
    static let unaskedSkips: Set<String> = [
        MutationAdapter.notRequestedReason, SnapshotWorkspace.backfillToolSkipReason
    ]
    /// What says what became of a scan's own run, before `failed` or `was
    /// skipped`.
    static let ownRunLead = "this scan's mutation run "

    /// Why `held` can't be carried onto `snapshot`, a scan of the same
    /// package, commit and dirtiness whose SwiftMutator collector didn't
    /// run; nil when it can.
    static func refusal(of held: HeldMutation, onto snapshot: ScannedSnapshot) -> String? {
        refusal(of: held, git: snapshot.info.git, records: snapshot.report.records, files: snapshot.report.files)
    }

    /// Why `held` can't be carried onto a scan at `git` whose records and
    /// files are `records` and `files`; nil when it can.
    static func refusal(
        of held: HeldMutation,
        git: GitState,
        records: [FunctionRecord],
        files: [FileRecord]
    ) -> String? {
        stateRefusal(of: held, git: git)
            ?? recordsRefusal(of: held, onto: records)
            ?? filesRefusal(of: held.results.report.mutants, onto: files)
            ?? unparsedRefusal(of: held.results.report.mutants, onto: files)
    }

    /// Why `held` can't be carried onto any scan at `git` by this build,
    /// whatever it parses: the reasons known before a scan runs; nil when
    /// there is none.
    static func stateRefusal(of held: HeldMutation, git: GitState) -> String? {
        guard held.git.commit != nil, git.commit != nil else {
            return "no git commit to compare against"
        }
        guard held.git.isDirty == git.isDirty, held.git.dirtyHash == git.dirtyHash else {
            return "the uncommitted changes differ"
        }
        guard held.run.options.contains("map: " + MutationMapper.rule) else {
            return "it was mapped by another rule"
        }
        return nil
    }

    /// Why a record `held`'s mutants name isn't a production record among
    /// `records` over the lines it spanned, or a production record among
    /// `records` wasn't one of the held snapshot's, so the results never
    /// mapped onto it, naming the first such key; nil when neither.
    private static func recordsRefusal(of held: HeldMutation, onto records: [FunctionRecord]) -> String? {
        let production = Dictionary(
            records.filter { $0.role == .production }.map { record in
                let lines = (start: record.range.start.line, end: record.range.end.line)
                return (record.key, HeldMutation.Span(file: record.file, startLine: lines.start, endLine: lines.end))
            }
        ) { first, _ in first }
        let named = Set(held.results.report.mutants.filter { $0.place == .record }.compactMap(\.owner))
        for key in named.sorted() {
            guard let span = production[key] else {
                return "`\(key)` names no record now"
            }
            guard held.spans[key] == span else {
                return "`\(key)` spans other lines now"
            }
        }
        // A record the held scan didn't have (a file no longer excluded,
        // a build extracting more records) would read as holding no
        // mutant, though a fresh mapping could place some on it.
        if let added = production.keys.filter({ held.spans[$0] == nil }).min() {
            return "`\(added)` has no mutation results"
        }
        return nil
    }

    /// Why a mutant among `mutants` left unmapped because its file wasn't
    /// parsed (excluded, or not parsed) lies in a file among `files`, which
    /// the scan now parses, so a fresh mapping would place it, naming the
    /// first such path; nil when none does. Paths are compared in NFC.
    static func unparsedRefusal(of mutants: [Mutant], onto files: [FileRecord]) -> String? {
        let scanned = Set(files.map { NFCPath($0.path) })
        let reasons: Set<String> = [PackageFileClassifier.excludedReason, PackageFileClassifier.notParsedReason]
        return mutants.filter { $0.place == .unmapped && reasons.contains($0.reason ?? "") }
            .map { NFCPath($0.path) }
            .filter(scanned.contains)
            .min()
            .map { "`\($0)` is scanned now, but its mutants weren't mapped" }
    }

    /// Why a file holding mapped mutants among `mutants` isn't among
    /// `files` with the bytes those mutants were tested on, naming the
    /// first such path; nil when each is. Paths are compared in NFC, as
    /// the mapping compares them.
    static func filesRefusal(of mutants: [Mutant], onto files: [FileRecord]) -> String? {
        let scanned = Dictionary(files.map { (NFCPath($0.path), $0.sha256) }) { first, _ in first }
        let mapped = mutants.filter { [.record, .type, .file].contains($0.place) }
            .map { (path: NFCPath($0.path), hash: $0.fileSHA256) }
            .sorted { $0.path < $1.path }
        for mutant in mapped {
            guard let hash = scanned[mutant.path] else {
                return "`\(mutant.path)` isn't scanned now"
            }
            guard mutant.hash == hash else {
                return "`\(mutant.path)` holds other bytes now"
            }
        }
        return nil
    }

    /// What became of `snapshot`'s own SwiftMutator run when it was asked
    /// for and didn't run: "this scan's mutation run failed (…)" or "was
    /// skipped (…)", with its reason; nil when it ran, wasn't asked for, or
    /// isn't there.
    static func ownRun(of snapshot: ScannedSnapshot) -> String? {
        guard let run = snapshot.info.collectors.first(where: { $0.name == MutationAdapter.name }) else {
            return nil
        }
        return ownRun(state: run.state, reason: run.reason)
    }

    /// What became of a SwiftMutator run that ended as `state` for
    /// `reason`, as `ownRun(of:)` says it.
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

    /// `snapshot` with `held`'s results and their warnings attached, its
    /// SwiftMutator run the original's with a reason saying when the
    /// results were collected, and the roll-ups' mutation results rebuilt;
    /// when `snapshot`'s own run was asked for and failed or was skipped, a
    /// warning says so, which a later carry doesn't repeat.
    static func carried(_ held: HeldMutation, onto snapshot: ScannedSnapshot) -> ScannedSnapshot {
        let collectedAt = held.results.collectedAt
        let notice = ownRun(of: snapshot).map { what in
            MutationSession.warning("\(what), so it keeps the results collected \(collectedAt)")
        }
        let run = held.run.carried(collectedAt: collectedAt)
        return ScannedSnapshot(
            info: snapshot.info.with(run: run),
            report: snapshot.report.with(
                mutation: held.results.report,
                status: run.status,
                warnings: held.warnings + [notice].compactMap(\.self)
            )
        )
    }
}

//
//  IndexCarry.swift
//  SwiftStatsCore
//
//  Keeping T1 results across a rescan whose build didn't run (M7, design
//  §9.4), as `CoverageCarry` and `MutationCarry` keep theirs: only
//  `scan --index` builds the package for the index, so a rescan of a
//  snapshot holding the build's, the index's and outskirts' results
//  carries all three when they still describe the scan, checked in this
//  order: both scans saw a commit; the tree is the same (both clean, or
//  both dirty with the same hash of the changes); every rule the results
//  were collected under is this build's (`build`'s `map:` and `warnings:`,
//  `index`'s `units:`, `usr:`, `references:` and `types:`, `periphery`'s
//  `classes:` and `map:`; a reader that was skipped or failed has none to
//  compare); the records are the same, of every role, each over the same
//  full span, in the same family and owned by the same type, and so are
//  the type records with their spans; and every scanned file has the
//  bytes the build hashed, with no file scanned now that wasn't then, or
//  the other way round. A SwiftStats rebuild that changes owning types,
//  families or start columns without changing a rule therefore refuses
//  rather than carry rows that name other things. A carried group keeps
//  each collector's original identity, version, options, duration and
//  state, its reason saying when the results were collected; the `swiftc`
//  findings and the warnings describing the results come with them, and
//  the roll-ups and line ratios are rebuilt from the blocks as a scan
//  builds them, the type-check totals read back from their roll-up
//  rows. A rescan whose build was asked for and failed or was
//  skipped says so in a warning. Otherwise the rescan is refused, saying
//  why, and why the build asked for didn't run.
//

/// Decides whether stored T1 results carry onto a rescan, and carries
/// them.
enum IndexCarry {
    /// The T1 collectors' names, in the order they run.
    static let names = [BuildAdapter.name, IndexAdapter.name, PeripheryAdapter.name]
    /// Skip reasons a build gives when it wasn't asked for: a plain
    /// scan's, and a backfill's without tools.
    static let unaskedSkips: Set<String> = [
        BuildAdapter.notRequestedReason, SnapshotWorkspace.backfillToolSkipReason
    ]
    /// The rules each T1 collector's results were collected under, as its
    /// options name them.
    private static let rules: [(collector: String, option: String)] = [
        (BuildAdapter.name, "map: " + TimingMapper.rule),
        (BuildAdapter.name, "warnings: " + WarningReader.rule),
        (IndexAdapter.name, "units: " + UnitFilter.rule),
        (IndexAdapter.name, "usr: " + USRJoin.rule),
        (IndexAdapter.name, "references: " + ReferenceGraph.rule),
        (IndexAdapter.name, "types: " + TypeOwnership.rule),
        (PeripheryAdapter.name, "classes: " + PeripheryOutput.rule),
        (PeripheryAdapter.name, "map: " + DeadCodeMapper.rule)
    ]

    /// Whether `warning` is one a T1 collector gave describing its
    /// results, which a carry keeps: a warning on no file led by
    /// `build: `, `index: ` or `periphery: `, but for the carry's own
    /// notice about a failed build, which a later carry doesn't repeat.
    static func describesResults(_ warning: ScanWarning) -> Bool {
        guard warning.file == nil, warning.message.hasPrefix(notice("")) == false else {
            return false
        }
        return names.contains { warning.message.hasPrefix($0 + ": ") }
    }

    /// Why `held` can't be carried onto `snapshot`, a scan of the same
    /// package, commit and dirtiness whose build didn't run; nil when it
    /// can.
    static func refusal(of held: HeldIndex, onto snapshot: ScannedSnapshot) -> String? {
        refusal(
            of: held,
            git: snapshot.info.git,
            records: snapshot.report.records,
            types: snapshot.report.types,
            files: snapshot.report.files
        )
    }

    /// Why `held` can't be carried onto a scan at `git` whose records,
    /// type records and files are `records`, `types` and `files`; nil when
    /// it can.
    static func refusal(
        of held: HeldIndex,
        git: GitState,
        records: [FunctionRecord],
        types: [TypeRecord],
        files: [FileRecord]
    ) -> String? {
        stateRefusal(of: held, git: git)
            ?? recordsRefusal(of: held, onto: records)
            ?? typesRefusal(of: held, onto: types)
            ?? filesRefusal(of: held, onto: files)
    }

    /// Why `held` can't be carried onto any scan at `git` by this build,
    /// whatever it parses: the reasons known before a scan runs; nil when
    /// there is none.
    static func stateRefusal(of held: HeldIndex, git: GitState) -> String? {
        guard held.git.commit != nil, git.commit != nil else {
            return "no git commit to compare against"
        }
        guard held.git.isDirty == git.isDirty, held.git.dirtyHash == git.dirtyHash else {
            return "the uncommitted changes differ"
        }
        for (collector, option) in rules {
            guard let run = held.runs.first(where: { $0.name == collector }), run.state == .ran else {
                continue
            }
            guard run.options.contains(option) else {
                let lead = option.prefix { $0 != " " }
                return "`\(collector)` was collected under another `\(lead)` rule"
            }
        }
        return nil
    }

    /// Why the records of `held` aren't `records`, naming the first key
    /// in order that differs: a held record that is gone, in another file,
    /// over another span, in another family or owned by another type;
    /// then a record the held scan didn't have. Nil when they are the
    /// same.
    private static func recordsRefusal(of held: HeldIndex, onto records: [FunctionRecord]) -> String? {
        let scanned = HeldIndex.places(of: records)
        for key in held.records.keys.sorted() {
            guard let place = scanned[key], let was = held.records[key] else {
                return "`\(key)` names no record now"
            }
            if place.file != was.file {
                return "`\(key)` is in another file now"
            }
            if place.range != was.range {
                return "`\(key)` spans other lines or columns now"
            }
            if place.family != was.family {
                return "`\(key)` belongs to another family now"
            }
            if place.typePath != was.typePath || place.typeFile != was.typeFile {
                return "`\(key)` belongs to another type now"
            }
        }
        if let added = scanned.keys.filter({ held.records[$0] == nil }).min() {
            return "`\(added)` has no index results"
        }
        return nil
    }

    /// Why the type records of `held` aren't `types`, naming the first in
    /// order that differs: a held type that is gone or over another span,
    /// then a type the held scan didn't have. Nil when they are the same.
    private static func typesRefusal(of held: HeldIndex, onto types: [TypeRecord]) -> String? {
        let scanned = types.map(HeldIndex.TypeSpan.init)
        let missing = multiset(held.types, without: scanned)
        if let first = missing.min() {
            let moved = scanned.contains { $0.module == first.module && $0.name == first.name && $0.file == first.file }
            let what = moved ? "spans other lines or columns now" : "is gone now"
            return "type `\(first.name)` in `\(first.file)` \(what)"
        }
        if let added = multiset(scanned, without: held.types).min() {
            return "type `\(added.name)` in `\(added.file)` has no index results"
        }
        return nil
    }

    /// The elements of `values` left once each of `removed` takes one
    /// equal element away.
    private static func multiset(_ values: [HeldIndex.TypeSpan], without removed: [HeldIndex.TypeSpan])
        -> [HeldIndex.TypeSpan] {
        var counts = removed.reduce(into: [HeldIndex.TypeSpan: Int]()) { counts, value in
            counts[value, default: 0] += 1
        }
        return values.filter { value in
            guard let count = counts[value], count > 0 else {
                return true
            }
            counts[value] = count - 1
            return false
        }
    }

    /// Why a file among `files` isn't one `held` hashed with the same
    /// bytes, or a file `held` hashed isn't among them, naming the first
    /// path in order; nil when the files are the same.
    private static func filesRefusal(of held: HeldIndex, onto files: [FileRecord]) -> String? {
        for file in files.sorted(by: { $0.path < $1.path }) {
            guard let hash = held.files[file.path] else {
                return "`\(file.path)` is scanned now, but wasn't when the index was built"
            }
            guard hash == file.sha256 else {
                return "`\(file.path)` holds other bytes now"
            }
        }
        let scanned = Set(files.map(\.path))
        if let gone = held.files.keys.filter({ scanned.contains($0) == false }).min() {
            return "`\(gone)` isn't scanned now"
        }
        return nil
    }

    /// What became of `snapshot`'s own build when it was asked for and
    /// didn't run: "this scan's index build failed (…)" or "was skipped
    /// (…)", with its reason; nil when it ran, wasn't asked for, or isn't
    /// there.
    static func ownRun(of snapshot: ScannedSnapshot) -> String? {
        guard let run = snapshot.info.collectors.first(where: { $0.name == BuildAdapter.name }) else {
            return nil
        }
        return ownRun(state: run.state, reason: run.reason)
    }

    /// What became of a build that ended as `state` for `reason`, as
    /// `ownRun(of:)` says it.
    static func ownRun(state: CollectorState, reason given: String?) -> String? {
        if state == .skipped, unaskedSkips.contains(given ?? "") {
            return nil
        }
        return BuildAdapter.ownRun(state: state, reason: given)
    }

    /// The warning saying that this scan's build, which ended as `what`
    /// says, keeps the results collected at `collectedAt`; with an empty
    /// `what`, what every such warning starts with.
    private static func notice(_ what: String) -> String {
        what.isEmpty ? "\(BuildAdapter.name): \(BuildAdapter.ownRunLead)" : "\(BuildAdapter.name): \(what)"
    }

    /// `snapshot` with `held`'s results attached: its three runs the
    /// original ones with a reason saying when the results were collected,
    /// each in the state it ended in; the build, index and dead-code
    /// blocks, the `swiftc` findings and the warnings describing them
    /// attached, and the roll-ups and line ratios rebuilt from them. When
    /// `snapshot`'s own build was asked for and failed or was skipped, a
    /// warning says so, which a later carry doesn't repeat.
    static func carried(_ held: HeldIndex, onto snapshot: ScannedSnapshot) -> ScannedSnapshot {
        let collectedAt = held.collectedAt
        let notice = ownRun(of: snapshot).map { what in
            ScanWarning(file: nil, message: notice("\(what), so it keeps the results collected \(collectedAt)"))
        }
        let runs = held.runs.map { $0.carried(collectedAt: collectedAt, keeping: $0.state) }
        let status = { (name: String) in
            runs.first { $0.name == name }?.status
                ?? CollectorStatus(name: name, state: .skipped, version: nil, reason: nil, options: [])
        }
        let report = snapshot.report
            .with(build: held.buildReport, totals: held.typeCheckTotals, status: status(BuildAdapter.name))
            .with(index: held.index, status: status(IndexAdapter.name))
            .with(deadCode: held.deadCode, status: status(PeripheryAdapter.name))
            .with(findings: held.findings, of: WarningReader.tool)
            .with(warnings: held.warnings + [notice].compactMap(\.self))
        return ScannedSnapshot(info: runs.reduce(snapshot.info) { $0.with(run: $1) }, report: report)
    }
}

//
//  SnapshotWorkspace+Held.swift
//  SwiftStatsCore
//
//  Held results decided before the slow runs, and a SwiftMutator run's
//  results kept until its snapshot is stored (M6, design §6.4, as built;
//  review findings 4 and 16; M7, design §9.5). A scan asking for coverage,
//  the T1 group or SwiftMutator would otherwise learn only at save time,
//  after a run of seconds to an hour, that the snapshot it replaces holds
//  results it can't keep. So, before anything runs, held coverage, mutation
//  results and T1 results of the kinds the scan doesn't ask for are
//  refused as the save would refuse them for reasons the git state already
//  settles (no commit, other uncommitted changes, another rule), or for
//  being too damaged to read. Once SwiftInferProperties, the coverage run
//  and the clone detector have finished, just before the T1 build starts
//  (`IndexSaving`), held coverage the scan didn't collect (not asked for,
//  failed or skipped) and held mutation results it doesn't ask for are
//  decided in full, their records included, as the save will decide them;
//  held T1 results aren't, since a build that runs replaces them. Once
//  every other collector has finished, just before SwiftMutator starts
//  (`MutationSaving`), held coverage the scan didn't collect and held T1
//  results whose build it didn't run are decided in full too. Each
//  refusal has the save's own words, and `--drop-coverage`,
//  `--drop-mutation` and `--drop-index` pass as they do there. Should the
//  save still refuse after a SwiftMutator run that ran, its results stay
//  named in `pending.json`, so `scan --mutation --resume` stores them
//  without running SwiftMutator again, as the refusal then says; once the
//  snapshot is stored, the record goes. A plain scan isn't checked: its
//  save refuses at once anyway.
//

extension SnapshotWorkspace {
    /// Refuses, before anything runs, a scan at `git` asking for `tiers`
    /// whose save would refuse held results it doesn't ask for, for
    /// reasons the git state settles; for a scan asking for the T1 group,
    /// the check of held coverage and mutation results before the build
    /// starts, and for one asking for SwiftMutator, what it adds to the
    /// run: the check of held coverage and T1 results before SwiftMutator
    /// starts, and keeping a run that ran until it is stored. Both nil for
    /// a scan asking for none of the slow collectors, which isn't checked.
    func heldResultsChecks(
        git: GitState,
        tiers: RequestedTiers,
        drop: DropOptions
    ) throws -> (mutation: MutationSaving?, index: IndexSaving?) {
        guard tiers.coverage || tiers.index || tiers.mutation != nil else {
            return (nil, nil)
        }
        let package = try describer.describePackage(at: root).name
        let held = try store.snapshotID(
            package: package,
            packagePath: git.packagePath,
            commit: git.commit,
            isDirty: git.isDirty
        )
        .map { slot in HeldSlot(id: slot, name: Self.name(package: package, git: git), git: git, drop: drop) }
        if let held {
            try stateChecks(of: held, tiers: tiers)
        }
        let mutation = MutationSaving { coverage, build, measured in
            guard let held else {
                return
            }
            try fullCoverageCheck(of: held, coverage: coverage, records: measured.records)
            try fullIndexCheck(of: held, build: build, measured: measured)
        }
        let index = IndexSaving { coverage, measured in
            guard let held else {
                return
            }
            try fullCoverageCheck(of: held, coverage: coverage, records: measured.records)
            if tiers.mutation == nil {
                try fullMutationCheck(of: held, measured: measured)
            }
        }
        return (tiers.mutation == nil ? nil : mutation, tiers.index ? index : nil)
    }

    /// Refuses, before anything runs, a scan asking for `tiers` over
    /// `held`'s snapshot whose save would refuse held results of a kind
    /// the scan doesn't ask for, for reasons the git state settles, or for
    /// being too damaged to read, unless `held` lets them go.
    private func stateChecks(of held: HeldSlot, tiers: RequestedTiers) throws {
        if tiers.coverage == false {
            _ = try keptCoverage(in: held.id, named: held.name, drop: held.drop.contains(.coverage)) { results in
                CoverageCarry.stateRefusal(of: results, git: held.git)
            }
        }
        if tiers.mutation == nil {
            _ = try keptMutation(in: held.id, named: held.name, drop: held.drop.contains(.mutation)) { results in
                MutationCarry.stateRefusal(of: results, git: held.git)
            }
        }
        if tiers.index == false {
            _ = try keptIndex(in: held.id, named: held.name, drop: held.drop.contains(.index)) { results in
                IndexCarry.stateRefusal(of: results, git: held.git)
            }
        }
    }

    /// Refuses, once the coverage collector has ended as `coverage` says,
    /// a scan whose measured records are `records` over the held coverage
    /// of `held`'s snapshot that it didn't collect and that doesn't carry
    /// onto them, in the save's words, unless `held` lets it go; nothing
    /// when the coverage run ran.
    private func fullCoverageCheck(of held: HeldSlot, coverage: CollectorStatus, records: [FunctionRecord]) throws {
        guard coverage.state != .ran else {
            return
        }
        _ = try keptCoverage(in: held.id, named: held.name, drop: held.drop.contains(.coverage)) { results in
            CoverageCarry.refusal(of: results, git: held.git, records: records).map { reason in
                [reason, CoverageCarry.ownRun(state: coverage.state, reason: coverage.reason)]
                    .compactMap(\.self)
                    .joined(separator: "; ")
            }
        }
    }

    /// Refuses a scan that doesn't ask for SwiftMutator, measured as
    /// `measured`, over held mutation results of `held`'s snapshot that
    /// don't carry onto it, in the save's words, unless `held` lets them
    /// go.
    private func fullMutationCheck(of held: HeldSlot, measured: ScanMeasurements) throws {
        _ = try keptMutation(in: held.id, named: held.name, drop: held.drop.contains(.mutation)) { results in
            MutationCarry.refusal(of: results, git: held.git, records: measured.records, files: measured.files)
        }
    }

    /// Refuses, once the build has ended as `build` says, a scan measured
    /// as `measured` over held T1 results of `held`'s snapshot that don't
    /// carry onto it, in the save's words, unless `held` lets them go;
    /// nothing when the build ran, which replaces them.
    private func fullIndexCheck(of held: HeldSlot, build: CollectorStatus, measured: ScanMeasurements) throws {
        guard build.state != .ran else {
            return
        }
        _ = try keptIndex(in: held.id, named: held.name, drop: held.drop.contains(.index)) { results in
            IndexCarry.refusal(
                of: results,
                git: held.git,
                records: measured.records,
                types: measured.types,
                files: measured.files
            )
            .map { reason in
                [reason, IndexCarry.ownRun(state: build.state, reason: build.reason)]
                    .compactMap(\.self)
                    .joined(separator: "; ")
            }
        }
    }

    /// Stores `snapshot` as `save(_:drop:)` does; then forgets the results
    /// its SwiftMutator run kept until it was stored. When the save is
    /// refused, they stay kept, and a store error says so
    /// (`StoreError.mutationResultsKept`).
    func storing(_ snapshot: ScannedSnapshot, drop: DropOptions) throws -> (snapshot: ScannedSnapshot, id: Int64) {
        let kept = keptResults(of: snapshot)
        let stored: (snapshot: ScannedSnapshot, id: Int64)
        do {
            stored = try save(snapshot, drop: drop)
        } catch let error as StoreError where kept != nil {
            let advised = switch error {
            case .coverageNotKept, .damagedCoverage, .mutationNotKept, .damagedMutation, .indexNotKept, .damagedIndex:
                true

            default:
                false
            }
            throw StoreError.mutationResultsKept(refusal: error.description, advised: advised)
        }
        if let kept {
            forget(kept)
        }
        return stored
    }

    /// The results file `pending.json` keeps for `snapshot`'s SwiftMutator
    /// run, from the package root; nil when it keeps none of its runs'.
    private func keptResults(of snapshot: ScannedSnapshot) -> String? {
        let directory = MutationDirectory(lookingIn: root)
        guard let runs = snapshot.report.mutation?.runs,
              let file = (try? PendingMutationRun.read(in: directory))??.kept?.resultsFile,
              runs.contains(where: { $0.resultsFile == file }) else {
            return nil
        }
        return file
    }

    /// Removes `pending.json` while it keeps the results file `file`,
    /// holding the package's mutation lock; left as it is when another
    /// step holds the lock, whose run replaces it anyway.
    private func forget(_ file: String) {
        let directory = MutationDirectory(lookingIn: root)
        try? MutationLock.holding(directory.lock) { () throws(MutationFailure) in
            guard try PendingMutationRun.read(in: directory)?.kept?.resultsFile == file else {
                return
            }
            try PendingMutationRun.remove(in: directory)
        }
    }
}

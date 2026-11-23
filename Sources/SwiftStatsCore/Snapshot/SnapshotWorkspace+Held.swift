//
//  SnapshotWorkspace+Held.swift
//  SwiftStatsCore
//
//  Held results decided before the slow runs, and a SwiftMutator run's
//  results kept until its snapshot is stored (M6, design §6.4, as built;
//  review findings 4 and 16). A scan asking for coverage or SwiftMutator
//  would otherwise learn only at save time, after a run of minutes or an
//  hour, that the snapshot it replaces holds results it can't keep. So,
//  before anything runs, held coverage the scan doesn't ask for, and held
//  mutation results it doesn't ask for, are refused as the save would
//  refuse them for reasons the git state already settles (no commit, other
//  uncommitted changes, another mapping or linking rule), or for being
//  too damaged to read; and once every other collector has finished, just
//  before SwiftMutator starts, held coverage the scan didn't collect (not
//  asked for, failed or skipped) is decided in full, its records included,
//  as the save will decide it. Each refusal has the save's own words, and
//  `--drop-coverage` and `--drop-mutation` pass as they do there. Should
//  the save still refuse after a run that ran, its results stay named in
//  `pending.json`, so `scan --mutation --resume` stores them without
//  running SwiftMutator again, as the refusal then says; once the snapshot
//  is stored, the record goes.
//

extension SnapshotWorkspace {
    /// Refuses, before anything runs, a scan at `git` asking for `tiers`
    /// whose save would refuse held results it doesn't ask for, for
    /// reasons the git state settles; for a scan asking for SwiftMutator,
    /// what it adds to the run: the check of held coverage before
    /// SwiftMutator starts, and keeping a run that ran until it is stored.
    /// Nil for a scan asking for neither slow collector, which isn't checked.
    func heldResultsChecks(git: GitState, tiers: RequestedTiers, drop: DropOptions) throws -> MutationSaving? {
        guard tiers.coverage || tiers.mutation != nil else {
            return nil
        }
        let package = try describer.describePackage(at: root).name
        let name = Self.name(package: package, git: git)
        let slot = try store.snapshotID(
            package: package,
            packagePath: git.packagePath,
            commit: git.commit,
            isDirty: git.isDirty
        )
        if let slot, tiers.coverage == false {
            _ = try keptCoverage(in: slot, named: name, drop: drop.contains(.coverage)) { held in
                CoverageCarry.stateRefusal(of: held, git: git)
            }
        }
        if let slot, tiers.mutation == nil {
            _ = try keptMutation(in: slot, named: name, drop: drop.contains(.mutation)) { held in
                MutationCarry.stateRefusal(of: held, git: git)
            }
        }
        guard tiers.mutation != nil else {
            return nil
        }
        return MutationSaving { coverage, records in
            guard let slot, coverage.state != .ran else {
                return
            }
            _ = try keptCoverage(in: slot, named: name, drop: drop.contains(.coverage)) { held in
                CoverageCarry.refusal(of: held, git: git, records: records).map { reason in
                    [reason, CoverageCarry.ownRun(state: coverage.state, reason: coverage.reason)]
                        .compactMap(\.self)
                        .joined(separator: "; ")
                }
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
            case .coverageNotKept, .damagedCoverage, .mutationNotKept, .damagedMutation:
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

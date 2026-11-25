//
//  SnapshotWorkspace+Save.swift
//  SwiftStatsCore
//
//  The one way a workspace stores a scan (PRD §6.2; M5, M6, design §6.4),
//  shared by `scan`, `diff`'s scans and `backfill`. A scan replaces the
//  snapshot of the same package, commit and dirtiness, but coverage is
//  collected only by `scan --coverage` and mutation results only by
//  `scan --mutation`, so a scan whose collector for either didn't run, or
//  whose run failed, carries what the replaced snapshot holds
//  (`CoverageCarry`, `MutationCarry`) or, when it can't, is refused before
//  anything is written, saying why and, when it was asked for, why the
//  scan's own run didn't collect it, unless `--drop-coverage` or
//  `--drop-mutation` lets those results go, as they do results too damaged
//  to read. Both held results are decided before any write, coverage
//  first, then mutation, and the first refusal stops the save; what
//  carries is written once. Held T1 results (M7) are decided last: until
//  their carry is built, a scan whose build didn't run is refused when
//  the replaced snapshot holds them, unless `--drop-index` lets them go. Only a run that ran replaces held results
//  without asking. A scan asking for coverage or SwiftMutator meets the
//  same refusals before its slow runs, as far as they can be known then
//  (`SnapshotWorkspace+Held`).
//

extension SnapshotWorkspace {
    /// How many characters of a commit a refusal shows.
    private static let shortCommitLength = 10
    /// Why held T1 results aren't carried yet (design §13's placeholder
    /// from step 7a to step 8).
    static let indexNotCarried = "this SwiftStats build can't carry index results yet"

    /// How a refusal names the snapshot `info` describes: its package and
    /// commit, and whether it has uncommitted changes.
    private static func name(of info: SnapshotInfo) -> String {
        name(package: info.package, git: info.git)
    }

    /// How a refusal names the snapshot of `package` at `git`.
    static func name(package: String, git: GitState) -> String {
        guard let commit = git.commit else {
            return "\(package) (no git commit)"
        }
        return "\(package) at \(commit.prefix(Self.shortCommitLength))"
            + (git.isDirty ? " with uncommitted changes" : "")
    }

    /// Whether `snapshot`'s collector `name` ran.
    private static func ran(_ name: String, in snapshot: ScannedSnapshot) -> Bool {
        snapshot.info.collectors.first { $0.name == name }?.state == .ran
    }

    /// Stores `snapshot`, replacing any snapshot of the same package,
    /// commit and dirtiness, and returns what it stored with its id. When
    /// the replaced snapshot holds coverage and `snapshot`'s coverage
    /// collector didn't run (skipped or failed), the coverage is carried
    /// onto it, or, when it can't be, `StoreError.coverageNotKept` is
    /// thrown and nothing is written; mutation results held where
    /// `snapshot`'s SwiftMutator collector didn't run are carried the same
    /// way, or refused with `StoreError.mutationNotKept`, coverage decided
    /// first. `drop` holding `.coverage` or `.mutation` replaces the
    /// snapshot without those results instead, but never drops results
    /// that carry. Results too damaged to read throw
    /// `StoreError.damagedCoverage` or `.damagedMutation`, naming the way
    /// past them, unless `drop` lets them go; any other failure to read
    /// them throws the store's error.
    @discardableResult
    func save(_ snapshot: ScannedSnapshot, drop: DropOptions) throws -> (snapshot: ScannedSnapshot, id: Int64) {
        let git = snapshot.info.git
        let replaced = try store.snapshotID(
            package: snapshot.info.package,
            packagePath: git.packagePath,
            commit: git.commit,
            isDirty: git.isDirty
        )
        let coverage = try carriedCoverage(from: replaced, onto: snapshot, drop: drop.contains(.coverage))
        let mutation = try carriedMutation(from: replaced, onto: snapshot, drop: drop.contains(.mutation))
        try refuseHeldIndex(in: replaced, onto: snapshot, drop: drop.contains(.index))
        var stored = snapshot
        if let coverage {
            stored = CoverageCarry.carried(coverage, onto: stored)
        }
        if let mutation {
            stored = MutationCarry.carried(mutation, onto: stored)
        }
        return (stored, try store.save(stored, coverageCollectedAt: coverage?.coverage.collectedAt))
    }

    /// The coverage snapshot `replaced` holds that `snapshot` carries: nil
    /// when `snapshot`'s coverage collector ran, there is no such snapshot
    /// or coverage, or `drop` lets coverage go that doesn't carry or can't
    /// be read. Throws the refusal when it doesn't carry, and
    /// `StoreError.damagedCoverage` when it can't be read, unless `drop`.
    private func carriedCoverage(
        from replaced: Int64?,
        onto snapshot: ScannedSnapshot,
        drop: Bool
    ) throws -> HeldCoverage? {
        guard let replaced, Self.ran(CoverageAdapter.name, in: snapshot) == false else {
            return nil
        }
        return try keptCoverage(in: replaced, named: Self.name(of: snapshot.info), drop: drop) { held in
            CoverageCarry.refusal(of: held, onto: snapshot).map { reason in
                [reason, CoverageCarry.ownRun(of: snapshot)].compactMap(\.self).joined(separator: "; ")
            }
        }
    }

    /// The mutation results snapshot `replaced` holds that `snapshot`
    /// carries: nil when `snapshot`'s SwiftMutator collector ran, there is
    /// no such snapshot or results, or `drop` lets results go that don't
    /// carry or can't be read. Throws the refusal when they don't carry,
    /// and `StoreError.damagedMutation` when they can't be read, unless
    /// `drop`.
    private func carriedMutation(
        from replaced: Int64?,
        onto snapshot: ScannedSnapshot,
        drop: Bool
    ) throws -> HeldMutation? {
        guard let replaced, Self.ran(MutationAdapter.name, in: snapshot) == false else {
            return nil
        }
        return try keptMutation(in: replaced, named: Self.name(of: snapshot.info), drop: drop) { held in
            MutationCarry.refusal(of: held, onto: snapshot).map { reason in
                [reason, MutationCarry.ownRun(of: snapshot)].compactMap(\.self).joined(separator: "; ")
            }
        }
    }

    /// Refuses a save that would replace the T1 results snapshot
    /// `replaced` holds with `snapshot`, whose build didn't run, unless
    /// `drop` lets them go. Until the same-tree carry is built (design §13
    /// step 8) no such results are carried, so the refusal says so.
    private func refuseHeldIndex(in replaced: Int64?, onto snapshot: ScannedSnapshot, drop: Bool) throws {
        guard let replaced, drop == false, Self.ran(BuildAdapter.name, in: snapshot) == false,
              let collectedAt = try store.indexCollectedAt(id: replaced)
        else {
            return
        }
        throw StoreError.indexNotKept(
            snapshot: Self.name(of: snapshot.info),
            collectedAt: collectedAt,
            reason: Self.indexNotCarried
        )
    }

    /// The coverage snapshot `id`, named `name`, holds when `refusal`
    /// gives no reason it can't be kept: nil when it holds none, or `drop`
    /// lets coverage go that can't be kept or read. Throws
    /// `StoreError.coverageNotKept` with `refusal`'s reason, and
    /// `StoreError.damagedCoverage` when it can't be read, unless `drop`.
    func keptCoverage(
        in id: Int64,
        named name: String,
        drop: Bool,
        refusal: (HeldCoverage) -> String?
    ) throws -> HeldCoverage? {
        guard try store.holdsCoverage(id: id) else {
            return nil
        }
        let read: HeldCoverage?
        do {
            read = try store.heldCoverage(id: id)
        } catch StoreError.corruptReport(let reason) where !drop {
            throw StoreError.damagedCoverage(snapshot: name, reason: reason)
        } catch {
            guard drop else {
                throw error
            }
            return nil
        }
        guard let held = read, let reason = refusal(held) else {
            return read
        }
        guard drop else {
            throw StoreError.coverageNotKept(snapshot: name, collectedAt: held.coverage.collectedAt, reason: reason)
        }
        return nil
    }

    /// The mutation results snapshot `id`, named `name`, holds when
    /// `refusal` gives no reason they can't be kept: nil when it holds
    /// none, or `drop` lets results go that can't be kept or read. Throws
    /// `StoreError.mutationNotKept` with `refusal`'s reason, and
    /// `StoreError.damagedMutation` when they can't be read, unless `drop`.
    func keptMutation(
        in id: Int64,
        named name: String,
        drop: Bool,
        refusal: (HeldMutation) -> String?
    ) throws -> HeldMutation? {
        guard try store.holdsMutation(id: id) else {
            return nil
        }
        let read: HeldMutation?
        do {
            read = try store.heldMutation(id: id)
        } catch StoreError.corruptReport(let reason) where !drop {
            throw StoreError.damagedMutation(snapshot: name, reason: reason)
        } catch {
            guard drop else {
                throw error
            }
            return nil
        }
        guard let held = read, let reason = refusal(held) else {
            return read
        }
        guard drop else {
            throw StoreError.mutationNotKept(snapshot: name, collectedAt: held.results.collectedAt, reason: reason)
        }
        return nil
    }
}

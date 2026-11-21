//
//  SnapshotWorkspace+Save.swift
//  SwiftStatsCore
//
//  The one way a workspace stores a scan (PRD §6.2; M5, design §6), shared
//  by `scan`, `diff`'s scans and `backfill`. A scan replaces the snapshot
//  of the same package, commit and dirtiness, but coverage is collected only
//  by `scan --coverage`, so a scan that didn't run the coverage collector,
//  or whose run failed, carries the coverage the replaced snapshot holds
//  (`CoverageCarry`) or, when it can't, is refused before anything is
//  written, unless `--drop-coverage` lets the coverage go. Only a coverage
//  run that ran replaces held coverage without asking.
//

extension SnapshotWorkspace {
    /// How many characters of a commit a refusal shows.
    private static let shortCommitLength = 10

    /// How a refusal names the snapshot `info` describes: its package and
    /// commit, and whether it has uncommitted changes.
    private static func name(of info: SnapshotInfo) -> String {
        guard let commit = info.git.commit else {
            return "\(info.package) (no git commit)"
        }
        return "\(info.package) at \(commit.prefix(Self.shortCommitLength))"
            + (info.git.isDirty ? " with uncommitted changes" : "")
    }

    /// Stores `snapshot`, replacing any snapshot of the same package,
    /// commit and dirtiness, and returns what it stored with its id. When
    /// the replaced snapshot holds coverage and `snapshot`'s coverage
    /// collector didn't run (skipped or failed), the coverage is carried
    /// onto it, or, when it can't be, `StoreError.coverageNotKept` is
    /// thrown and nothing is written; `dropCoverage` replaces it without
    /// coverage instead, but never drops coverage that carries.
    @discardableResult
    func save(_ snapshot: ScannedSnapshot, dropCoverage: Bool) throws -> (snapshot: ScannedSnapshot, id: Int64) {
        guard let held = try heldCoverage(replacedBy: snapshot) else {
            return (snapshot, try store.save(snapshot))
        }
        if let reason = CoverageCarry.refusal(of: held, onto: snapshot) {
            if dropCoverage {
                return (snapshot, try store.save(snapshot))
            }
            throw StoreError.coverageNotKept(
                snapshot: Self.name(of: snapshot.info),
                collectedAt: held.coverage.collectedAt,
                reason: reason
            )
        }
        let carried = CoverageCarry.carried(held, onto: snapshot)
        return (carried, try store.save(carried, coverageCollectedAt: held.coverage.collectedAt))
    }

    /// The coverage held by the snapshot `snapshot` would replace, when
    /// `snapshot`'s coverage collector didn't run (skipped, or failed); nil
    /// when it ran, or there is no such snapshot or coverage.
    private func heldCoverage(replacedBy snapshot: ScannedSnapshot) throws -> HeldCoverage? {
        let run = snapshot.info.collectors.first { $0.name == CoverageAdapter.name }
        guard run?.state != .ran else {
            return nil
        }
        let git = snapshot.info.git
        guard let replaced = try store.snapshotID(
            package: snapshot.info.package,
            packagePath: git.packagePath,
            commit: git.commit,
            isDirty: git.isDirty
        ) else {
            return nil
        }
        return try store.heldCoverage(id: replaced)
    }
}

//
//  SnapshotStore+Mutation.swift
//  SwiftStatsCore
//
//  Reading the mutation results a snapshot holds for a scan that builds on
//  them (M6, design §5, §6.1, §6.4): whether there are any is checked
//  first without reading them, as for coverage, so results too damaged to
//  read can still be dropped, and then only the snapshot's mutation rows
//  and its swiftmutator run are read, never the report blob but for the
//  warnings describing the results when a rescan may carry them. A
//  snapshot holds mutation results when its swiftmutator run ran and it
//  has a `mutationScan` row. `scan --mutation --since` reads the results of
//  its base this way, and names the nearest snapshot that holds complete
//  ones when its base holds none; a rescan of the same tree reads those of
//  the snapshot it replaces, with its production records' spans.
//

import GRDB

extension SnapshotStore {
    /// Whether snapshot `id` holds mutation results, read in `database`: a
    /// `mutationScan` row beside a swiftmutator run that ran. Nothing of
    /// the results themselves is read.
    static func holdsMutation(id: Int64, in database: Database) throws -> Bool {
        try Bool.fetchOne(
            database,
            sql: """
                SELECT EXISTS (SELECT 1 FROM mutationScan WHERE snapshotId = ?)
                    AND EXISTS (SELECT 1 FROM collectorRun WHERE snapshotId = ? AND name = ? AND state = ?)
                """,
            arguments: [id, id, MutationAdapter.name, CollectorState.ran.rawValue]
        ) ?? false
    }

    /// The mutation results snapshot `id` holds, read back from its rows
    /// in `database`, with its swiftmutator run; nil when it holds none.
    /// Rows too damaged to read throw the store's error.
    static func mutationResults(
        id: Int64,
        in database: Database
    ) throws -> (results: StoredMutation, run: CollectorRunInfo)? {
        guard try holdsMutation(id: id, in: database),
              let rows = try MutationRows(id: id, in: database),
              let run = try info(id: id, in: database).collectors.first(where: { $0.name == MutationAdapter.name })
        else {
            return nil
        }
        return (try rows.stored, run)
    }

    /// The mutation results snapshot `id` holds, with its git state,
    /// swiftmutator run, the warnings describing them and its production
    /// records' spans, read in `database`, for a rescan that may carry
    /// them; nil when it holds none. Rows too damaged to read throw
    /// `StoreError.corruptReport`.
    static func heldMutation(id: Int64, in database: Database) throws -> HeldMutation? {
        guard try holdsMutation(id: id, in: database), let rows = try MutationRows(id: id, in: database) else {
            return nil
        }
        let snapshot = try info(id: id, in: database)
        guard let run = snapshot.collectors.first(where: { $0.name == MutationAdapter.name }) else {
            return nil
        }
        return HeldMutation(
            git: snapshot.git,
            run: run,
            results: try rows.stored,
            warnings: try storedWarnings(id: id, in: database).filter(MutationSession.describesResults),
            spans: try productionSpans(id: id, in: database)
        )
    }

    /// The commits of the clean snapshots of `package` at `packagePath`
    /// that hold complete mutation results, which can be a `--since`
    /// run's base, read in `database`.
    static func commitsHoldingMutation(
        package: String,
        packagePath: String,
        in database: Database
    ) throws -> Set<String> {
        let commits = try String.fetchAll(
            database,
            sql: """
                SELECT commitHash FROM snapshot
                WHERE package = ? AND packagePath = ? AND isDirty = 0 AND commitHash IS NOT NULL
                    AND EXISTS (SELECT 1 FROM mutationScan WHERE snapshotId = snapshot.id AND complete = 1)
                    AND EXISTS (
                        SELECT 1 FROM collectorRun
                        WHERE snapshotId = snapshot.id AND name = ? AND state = ?
                    )
                """,
            arguments: [package, packagePath, MutationAdapter.name, CollectorState.ran.rawValue]
        )
        return Set(commits)
    }
}

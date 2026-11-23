//
//  MutationScanRow.swift
//  SwiftStatsCore
//
//  The `mutationScan` row (M6, design §5): one per snapshot holding
//  mutation results, saying when and how they were made and whether they
//  are complete. Its counts aren't stored: every mutant is a row, dropped
//  and unmapped ones too, and the counts follow from them.
//

/// A snapshot's mutation results, as one row.
struct MutationScanRow: Codable, Equatable {
    /// The table name.
    static let databaseTableName = "mutationScan"

    /// The snapshot.
    var snapshotId: Int64
    /// When the results were collected.
    var collectedAt: String
    /// Whether every mutant the runs discovered has a result.
    var complete: Bool
    /// Whether the results list the mutants of code no test ran.
    var listsNotCovered: Bool
    /// `full` or `since`.
    var mode: MutationMode
    /// A merge's base commit; null for a full run.
    var baseCommit: String?
    /// When the base's results were collected; null for a full run.
    var baseCollectedAt: String?

    /// The base this row names; nil unless both its columns are set.
    var base: MutationSource? {
        guard let baseCommit, let baseCollectedAt else {
            return nil
        }
        return MutationSource(commit: baseCommit, collectedAt: baseCollectedAt)
    }

    /// The row for `report` in snapshot `snapshotId`.
    init(_ report: MutationReport, snapshotId: Int64) {
        self.snapshotId = snapshotId
        collectedAt = report.collectedAt
        complete = report.complete
        listsNotCovered = report.listsNotCovered
        mode = report.mode
        baseCommit = report.base?.commit
        baseCollectedAt = report.base?.collectedAt
    }
}

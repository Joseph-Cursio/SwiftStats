//
//  IndexScanRow.swift
//  SwiftStatsCore
//
//  The `indexScan` row (store v6, M7, design §9.1): one per snapshot
//  holding index results, with when they were collected, the store's
//  layout, its units counted by class, the library-product targets it
//  compiled (a JSON array of target names) and what the join counted.
//

import GRDB

/// A snapshot's index results, as one row.
struct IndexScanRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "indexScan"

    /// The snapshot.
    var snapshotId: Int64
    /// When the build the index comes from ran.
    var collectedAt: String
    /// The store's layout.
    var layout: String
    /// The library-product targets with units read, as a JSON array.
    var libraryModules: String
    /// Kept units.
    var unitsKept: Int
    /// Variant units.
    var unitsVariant: Int
    /// System units.
    var unitsSystem: Int
    /// Units of no package file.
    var unitsOtherPackage: Int
    /// Units of modules no target has.
    var unitsOtherModule: Int
    /// Stale units.
    var unitsStale: Int
    /// Older duplicate units.
    var unitsDuplicate: Int
    /// Units moved out of the store.
    var unitsQuarantined: Int
    /// Records read.
    var records: Int
    /// Occurrences read.
    var occurrences: Int
    /// Definitions joined to records.
    var definitionsJoined: Int
    /// Implicit definitions skipped.
    var definitionsImplicit: Int
    /// Secondary accessor USRs.
    var secondaryUSRs: Int
    /// `c:` USRs.
    var objcUSRs: Int

    /// The unit counts this row holds.
    var counts: IndexUnitCounts {
        IndexUnitCounts(
            system: unitsSystem,
            otherPackage: unitsOtherPackage,
            otherModule: unitsOtherModule,
            stale: unitsStale,
            duplicate: unitsDuplicate,
            variant: unitsVariant,
            kept: unitsKept,
            quarantined: unitsQuarantined
        )
    }

    /// The join's counts this row holds.
    var definitions: IndexDefinitions {
        IndexDefinitions(
            joined: definitionsJoined,
            implicit: definitionsImplicit,
            secondary: secondaryUSRs,
            objc: objcUSRs
        )
    }

    /// The row for `report`, collected at `collectedAt`, in snapshot
    /// `snapshotId`.
    init(_ report: IndexReport, collectedAt: String, snapshotId: Int64) {
        self.snapshotId = snapshotId
        self.collectedAt = collectedAt
        layout = report.store.layout
        libraryModules = RowJSON.text(report.libraryModules)
        let classes = report.store.counts
        unitsKept = classes.kept
        unitsVariant = classes.variant
        unitsSystem = classes.system
        unitsOtherPackage = classes.otherPackage
        unitsOtherModule = classes.otherModule
        unitsStale = classes.stale
        unitsDuplicate = classes.duplicate
        unitsQuarantined = classes.quarantined
        records = report.store.records
        occurrences = report.store.occurrences
        definitionsJoined = report.definitions.joined
        definitionsImplicit = report.definitions.implicit
        secondaryUSRs = report.definitions.secondary
        objcUSRs = report.definitions.objc
    }
}

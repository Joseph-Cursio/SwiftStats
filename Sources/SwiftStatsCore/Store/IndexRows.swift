//
//  IndexRows.swift
//  SwiftStatsCore
//
//  An index report as the store's v6 rows (M7, design §9.1, §9.2): the
//  scan row, each listed unit, each scanned file, the three USR listings,
//  each module edge, production type, family reference and family-type
//  reference, and each record's USRs and coupling, which are `function`
//  columns (`FunctionRow+Index`), read back in the order the snapshot wrote
//  its function rows, the scan's record order. The rows hold the report
//  whole, and it is put back together in the scan JSON's orders, so a scan
//  builds its index results through them (`normalized(_:)`): a fresh scan
//  and a carried one can't give different JSON. The store writes them
//  with the snapshot and reads them back (`SnapshotStore+Index`).
//

import GRDB

/// An index report's rows.
struct IndexRows: Equatable {
    /// The `function` columns read back, in the order the snapshot wrote
    /// its function rows.
    private static let recordColumns = """
        SELECT key, usr, usrAccessor, usrReason, witness, referrersSameModule, referrersOtherModules,
            referrersTests, testReferrers
        FROM function WHERE snapshotId = ? ORDER BY rowid
        """

    /// The scan row.
    let scan: IndexScanRow
    /// Each listed unit.
    let units: [StoredIndexUnitRow]
    /// Each scanned file.
    let files: [IndexFileRow]
    /// The disagreements, definitions with no record and collisions, by
    /// ordinal.
    let listings: [USRDisagreementRow]
    /// Each module edge.
    let edges: [ModuleEdgeRow]
    /// Each production type.
    let types: [TypeIndexRow]
    /// Each family reference.
    let familyReferences: [FamilyReferenceRow]
    /// Each family-type reference.
    let familyTypeReferences: [FamilyTypeReferenceRow]
    /// Each record's USRs and coupling, in the scan's record order: the
    /// `function` columns.
    let records: [IndexRecordUSR]

    /// The stored index results these rows hold; it throws a damaged store
    /// when a column doesn't read, never reading it as nothing.
    var stored: StoredIndex {
        get throws {
            do {
                return StoredIndex(collectedAt: scan.collectedAt, report: try report())
            } catch {
                throw StoreError.corruptReport("the index rows of snapshot \(scan.snapshotId)")
            }
        }
    }

    /// The rows of `report`, collected at `collectedAt`, in snapshot
    /// `snapshotId`.
    init(_ report: IndexReport, collectedAt: String, snapshotId: Int64) {
        scan = IndexScanRow(report, collectedAt: collectedAt, snapshotId: snapshotId)
        units = report.store.units.map { StoredIndexUnitRow($0, snapshotId: snapshotId) }
        files = report.files.map { IndexFileRow($0, snapshotId: snapshotId) }
        listings = (report.disagreements + report.withoutRecord + report.collisions).enumerated().map { ordinal, item in
            USRDisagreementRow(item, ordinal: ordinal, snapshotId: snapshotId)
        }
        edges = report.moduleEdges.map { ModuleEdgeRow($0, snapshotId: snapshotId) }
        types = report.types.map { TypeIndexRow($0, snapshotId: snapshotId) }
        familyReferences = report.familyReferences.map { FamilyReferenceRow($0, snapshotId: snapshotId) }
        familyTypeReferences = report.familyTypeReferences.map { FamilyTypeReferenceRow($0, snapshotId: snapshotId) }
        records = report.records
    }

    /// Snapshot `id`'s rows, read in `database`; nil when it holds no
    /// index results. A column that doesn't decode as its row's type, or a
    /// record column that doesn't read, throws a damaged store, as
    /// `stored` does.
    init?(id: Int64, in database: Database) throws {
        let mine = Column("snapshotId") == id
        do {
            guard let scanRow = try IndexScanRow.filter(mine).fetchOne(database) else {
                return nil
            }
            scan = scanRow
            units = try StoredIndexUnitRow.filter(mine).fetchAll(database)
            files = try IndexFileRow.filter(mine).fetchAll(database)
            listings = try USRDisagreementRow.filter(mine).order(Column("ordinal")).fetchAll(database)
            edges = try ModuleEdgeRow.filter(mine).fetchAll(database)
            types = try TypeIndexRow.filter(mine).fetchAll(database)
            familyReferences = try FamilyReferenceRow.filter(mine).fetchAll(database)
            familyTypeReferences = try FamilyTypeReferenceRow.filter(mine).fetchAll(database)
            records = try Row.fetchAll(database, sql: Self.recordColumns, arguments: [id]).map(Self.record)
        } catch is RowDecodingError {
            throw StoreError.corruptReport("the index rows of snapshot \(id)")
        } catch is DecodingError {
            throw StoreError.corruptReport("the index rows of snapshot \(id)")
        } catch is RowJSON.Unreadable {
            throw StoreError.corruptReport("the index rows of snapshot \(id)")
        }
    }

    /// `report` as its rows read it back. The rows always hold it whole;
    /// should they somehow not read back, `report` stands.
    static func normalized(_ report: IndexReport) -> IndexReport {
        (try? Self(report, collectedAt: "", snapshotId: 0).report()) ?? report
    }

    /// `report`'s records by key, as the snapshot's function rows take
    /// them.
    static func byKey(_ report: IndexReport) -> [String: IndexRecordUSR] {
        Dictionary(report.records.map { ($0.key, $0) }) { first, _ in first }
    }

    /// The record the `function` columns of `row` hold. Coupling is there
    /// when the witness flag is; then the referrer counts and test
    /// referrers must be too. It throws when a column doesn't read.
    private static func record(_ row: Row) throws -> IndexRecordUSR {
        let reason: String? = row["usrReason"]
        let witness: Int? = row["witness"]
        var coupling: IndexRecordCoupling?
        if let witness {
            let sameModule: Int? = row["referrersSameModule"]
            let otherModules: Int? = row["referrersOtherModules"]
            let tests: Int? = row["referrersTests"]
            let names: String? = row["testReferrers"]
            guard let sameModule, let otherModules, let tests, let names else {
                throw RowJSON.Unreadable(text: row["key"])
            }
            coupling = IndexRecordCoupling(
                witness: witness != 0,
                references: IndexReferences(
                    sameModule: sameModule,
                    otherModules: otherModules,
                    tests: tests,
                    testReferrers: try decodedNames(names)
                )
            )
        }
        return IndexRecordUSR(
            key: row["key"],
            usr: row["usr"],
            usrAccessor: row["usrAccessor"],
            reason: try reason.map { try RowJSON.named(USRReason.self, from: $0) },
            coupling: coupling
        )
    }

    /// The test referrers' names `text` holds as a JSON array.
    private static func decodedNames(_ text: String) throws -> [String] {
        do {
            return try RowJSON.decoded([String].self, from: text)
        } catch {
            throw RowJSON.Unreadable(text: text)
        }
    }

    /// The report these rows hold, in the scan JSON's orders: units by
    /// name and files by path (as the unit filter and the collector sort
    /// them), the listings by ordinal, and the edges, types and family
    /// references by their parts in code point order (as `ModuleEdges`
    /// and `IndexCoupling` sort them). It throws when a column doesn't
    /// read.
    func report() throws -> IndexReport {
        let listed = try listings.sorted { $0.ordinal < $1.ordinal }.map { try $0.listing }
        return IndexReport(
            store: IndexStoreSummary(
                layout: scan.layout,
                counts: scan.counts,
                records: scan.records,
                occurrences: scan.occurrences,
                units: try units.map { try $0.unit }.sorted { $0.name < $1.name }
            ),
            libraryModules: try RowJSON.decoded([String].self, from: scan.libraryModules),
            records: records,
            definitions: scan.definitions,
            disagreements: listed.filter { $0.kind == .severalUSRs || $0.kind == .sharedUSR },
            withoutRecord: listed.filter { $0.kind == .noRecord },
            collisions: listed.filter { $0.kind == .collision },
            moduleEdges: edges.map(\.edge).sorted { lhs, rhs in
                CodePointOrder.precedes([lhs.fromModule, lhs.toModule], [rhs.fromModule, rhs.toModule])
            },
            types: types.map(\.type).sorted { lhs, rhs in
                CodePointOrder.precedes(
                    [lhs.module, lhs.typePath, lhs.typeFile ?? "", lhs.usr],
                    [rhs.module, rhs.typePath, rhs.typeFile ?? "", rhs.usr]
                )
            },
            familyReferences: familyReferences.map(\.reference).sorted { lhs, rhs in
                CodePointOrder.precedes(
                    [lhs.fromFamily, lhs.toFamily, lhs.via.rawValue],
                    [rhs.fromFamily, rhs.toFamily, rhs.via.rawValue]
                )
            },
            familyTypeReferences: familyTypeReferences.map(\.reference).sorted { lhs, rhs in
                CodePointOrder.precedes(
                    [lhs.family, lhs.module, lhs.typePath, lhs.typeFile ?? ""],
                    [rhs.family, rhs.module, rhs.typePath, rhs.typeFile ?? ""]
                )
            },
            files: files.map(\.file).sorted { $0.path < $1.path }
        )
    }

    /// Inserts the rows in `database`, all but the records' columns,
    /// which go with the snapshot's function rows.
    func insert(_ database: Database) throws {
        try scan.insert(database)
        for row in units {
            try row.insert(database)
        }
        for row in files {
            try row.insert(database)
        }
        for row in listings {
            try row.insert(database)
        }
        for row in edges {
            try row.insert(database)
        }
        for row in types {
            try row.insert(database)
        }
        for row in familyReferences {
            try row.insert(database)
        }
        for row in familyTypeReferences {
            try row.insert(database)
        }
    }
}

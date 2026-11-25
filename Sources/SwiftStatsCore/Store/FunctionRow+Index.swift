//
//  FunctionRow+Index.swift
//  SwiftStatsCore
//
//  The `function` columns store v6 adds (M7, design §9.1): each record's
//  primary and secondary USR or the reason it has none, its witness flag
//  and referrers (test referrers' names as a JSON array), and its
//  type-check milliseconds and slowest expression. They are written with
//  the row, from the scan's `index` and `build` blocks, and read back only
//  by `IndexRows` and `BuildRows`, which turn a column that doesn't read
//  into the store's own error; `FunctionRow` itself doesn't hold them.
//  They are null when the collector didn't run and on rows written before
//  v6.
//

import GRDB

extension FunctionRow {
    /// A row with its v6 columns, as it is inserted.
    private struct Indexed: PersistableRecord {
        /// The table name.
        static let databaseTableName = FunctionRow.databaseTableName

        /// The row.
        let row: FunctionRow
        /// The record's USRs and coupling; nil when the index didn't run.
        let index: IndexRecordUSR?
        /// The record's type-check timings; nil when none were mapped to it.
        let timing: BuildRecordTiming?

        /// Writes the row's columns, then the v6 columns.
        func encode(to container: inout PersistenceContainer) throws {
            try row.encode(to: &container)
            container["usr"] = index?.usr
            container["usrAccessor"] = index?.usrAccessor
            container["usrReason"] = index?.reason?.rawValue
            let coupling = index?.coupling
            container["witness"] = coupling?.witness
            container["referrersSameModule"] = coupling?.references.sameModule
            container["referrersOtherModules"] = coupling?.references.otherModules
            container["referrersTests"] = coupling?.references.tests
            container["testReferrers"] = coupling.map { RowJSON.text($0.references.testReferrers) }
            container["typeCheckMilliseconds"] = timing?.milliseconds
            container["slowestExpressionMilliseconds"] = timing?.slowestExpression
        }
    }

    /// Inserts the row in `database` with its record's USRs and coupling,
    /// `index`, and its type-check timings, `timing`.
    func insert(_ database: Database, index: IndexRecordUSR?, timing: BuildRecordTiming?) throws {
        try Indexed(row: self, index: index, timing: timing).insert(database)
    }
}

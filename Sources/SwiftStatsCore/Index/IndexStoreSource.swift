//
//  IndexStoreSource.swift
//  SwiftStatsCore
//
//  The only way SwiftStats reaches an index store (M7, design §2.2): unit
//  names, a unit, a record, each copied out as SwiftStats' own values
//  (`IndexUnitFact`, `IndexRecordFact`). The product reads a real store
//  through `IndexStoreReader`, the one file linking indexstore-db's
//  `IndexStore`; unit tests read the checker's recorded dumps through
//  `RecordedIndexSource`. Everything SwiftStats does with the index (the
//  walk, the unit filter, the USR join, the reference graph) runs over this
//  protocol, so tests run that code over recorded reader output and never
//  need libIndexStore. A source never filters: classing units is
//  `UnitFilter`'s job.
//

/// Reads the units and records of one index store.
protocol IndexStoreSource {
    /// The name of every unit in the store, sorted in code point order.
    func unitNames() throws -> [String]

    /// The unit named `name`: its header, its records' names and its
    /// dependencies of kind `unit`.
    func unit(named name: String) throws -> IndexUnitFact

    /// The record named `name`, with every occurrence it holds.
    func record(named name: String) throws -> IndexRecordFact
}

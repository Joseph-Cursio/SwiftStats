//
//  IndexSnapshot.swift
//  SwiftStatsCore
//
//  What `IndexWalk` read from an index store (M7, design §2.2): every unit
//  with its class, and the records of the kept and variant units, each
//  once. Module names are translated to target names wherever the module
//  is one of the package's (design choice 5); another package's or a
//  system module keeps its C99 name. Paths under the package root are
//  given as paths in the package; others stay absolute.
//

/// The units and records read from one index store.
struct IndexSnapshot: Sendable {
    /// One unit and its class.
    struct Unit: Hashable, Sendable {
        /// The unit's name.
        let name: String
        /// Its class.
        let unitClass: UnitFilter.UnitClass
        /// Its module: the target name when the module is the package's,
        /// else the C99 name as stored.
        let module: String
        /// Whether `module` is one of the package's targets.
        let isPackageModule: Bool
        /// Its main file: a path in the package when under the root, else
        /// the absolute path as read ("" when it has none).
        let path: String
        /// The target triple.
        let triple: String
        /// The names of its records, sorted.
        let records: [String]
        /// The modules its main file imports (dependencies of kind `unit`,
        /// duplicates kept), translated as `module` is.
        let moduleDependencies: [IndexUnitFact.ModuleDependency]
    }

    /// One record of a kept or variant unit.
    struct Record: Hashable, Sendable {
        /// The record's name.
        let name: String
        /// Its source file: a path in the package when under the root,
        /// else the absolute path as read.
        let path: String
        /// Its occurrences, as read.
        let occurrences: [IndexOccurrenceFact]
    }

    /// Every unit of the store, by name.
    let units: [Unit]
    /// The records of the kept and variant units, by name, each once.
    let records: [Record]

    /// How many units each class holds; a class with none is absent.
    var counts: [UnitFilter.UnitClass: Int] {
        units.reduce(into: [:]) { counts, unit in counts[unit.unitClass, default: 0] += 1 }
    }

    /// The units whose records were read (`kept` and `variant`), by name.
    var readUnits: [Unit] {
        units.filter(\.unitClass.isRead)
    }
}

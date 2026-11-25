//
//  IndexWalk.swift
//  SwiftStatsCore
//
//  Reads an index store through any `IndexStoreSource` (M7, design §2.2):
//  every unit's header, classed by `UnitFilter`, then the records of the
//  kept and variant units only, each record once though several units may
//  name it, in name order. Reading dependency units' records would cost
//  seconds and isn't needed. Nothing is partial: a unit or record that
//  doesn't read fails the walk, naming it.
//

/// Walks an index store's units and records.
enum IndexWalk {
    /// A part of the store that didn't read.
    struct Failure: Error, CustomStringConvertible {
        /// What didn't read and why, for the `index` collector's reason.
        let description: String
    }

    /// The snapshot of the store `source` reads, classed by `filter`.
    static func walk(_ source: any IndexStoreSource, filter: UnitFilter) throws -> IndexSnapshot {
        let names = try reading("the unit list") { try source.unitNames() }
        let units = try names.map { name in
            try reading("unit \(name)") { try source.unit(named: name) }
        }
        let classed = filter.classify(units)
        var naming: [String: String] = [:]
        for entry in classed where entry.unitClass.isRead {
            for record in entry.unit.records where naming[record] == nil {
                naming[record] = entry.unit.name
            }
        }
        let records = try naming.keys.sorted().map { name in
            let fact = try reading("record \(name) of unit \(naming[name] ?? "")") { try source.record(named: name) }
            return IndexSnapshot.Record(
                name: fact.name,
                path: filter.packagePath(of: fact.file) ?? fact.file,
                occurrences: fact.occurrences
            )
        }
        return IndexSnapshot(units: classed.map { snapshotUnit($0, filter: filter) }, records: records)
    }

    /// `entry` as the snapshot gives it: module names translated, its main
    /// file as a path in the package.
    private static func snapshotUnit(_ entry: UnitFilter.ClassedUnit, filter: UnitFilter) -> IndexSnapshot.Unit {
        let unit = entry.unit
        let target = filter.target(of: unit.module)
        return IndexSnapshot.Unit(
            name: unit.name,
            unitClass: entry.unitClass,
            module: target ?? unit.module,
            isPackageModule: target != nil,
            path: filter.packagePath(of: unit.mainFile) ?? unit.mainFile,
            triple: unit.target,
            records: unit.records,
            moduleDependencies: unit.moduleDependencies.map { dependency in
                IndexUnitFact.ModuleDependency(
                    module: dependency.isSystem ? dependency.module : filter.target(of: dependency.module)
                        ?? dependency.module,
                    isSystem: dependency.isSystem
                )
            }
        )
    }

    /// The value `read` gives, or a `Failure` naming `what` and the error.
    private static func reading<Value>(_ what: String, _ read: () throws -> Value) throws -> Value {
        do {
            return try read()
        } catch {
            throw Failure(description: "\(what) doesn't read: \(error)")
        }
    }
}

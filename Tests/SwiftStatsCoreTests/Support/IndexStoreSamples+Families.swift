//
//  IndexStoreSamples+Families.swift
//  SwiftStatsCoreTests
//
//  The hand-made index block's family references renamed after the
//  families of the records it is made for, so that held T1 results name
//  only families their scan has, as a real index's do (M7, design §9.4:
//  a carry refuses held family references naming a family the rescan
//  doesn't have).
//

@testable import SwiftStatsCore

extension IndexStoreSamples {
    /// `index` with its family references naming the family of the first
    /// of `records` for `one()`'s and of the second for `two()`'s, as an
    /// index of `records` names them (`files` gives the same ids); the
    /// samples' own ids when there is no such record.
    static func named(_ index: IndexReport, families records: [FunctionRecord]) -> IndexReport {
        let places = HeldIndex.places(of: records)
        var renamed: [String: String] = [:]
        for (sample, record) in zip(["Lib::func one() -> Int", "Lib::func two()"], records) {
            renamed[sample] = places[record.key]?.family
        }
        let family = { (id: String) in renamed[id] ?? id }
        return IndexReport(
            store: index.store,
            libraryModules: index.libraryModules,
            records: index.records,
            definitions: index.definitions,
            disagreements: index.disagreements,
            withoutRecord: index.withoutRecord,
            collisions: index.collisions,
            moduleEdges: index.moduleEdges,
            types: index.types,
            familyReferences: index.familyReferences.map { reference in
                IndexFamilyReference(
                    fromFamily: family(reference.fromFamily),
                    toFamily: family(reference.toFamily),
                    via: reference.via
                )
            },
            familyTypeReferences: index.familyTypeReferences.map { reference in
                IndexFamilyTypeReference(
                    family: family(reference.family),
                    module: reference.module,
                    typePath: reference.typePath,
                    typeFile: reference.typeFile
                )
            },
            files: index.files
        )
    }
}

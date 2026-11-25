//
//  IndexUnitFact+Changes.swift
//  SwiftStatsCoreTests
//
//  Copies of a recorded unit with one field changed, for injecting units
//  beside a recording in the unit filter's, the index walk's and the USR
//  join's tests (M7, design §2.3, §3.1).
//

@testable import SwiftStatsCore

extension IndexUnitFact {
    /// This unit named `name`.
    func named(_ name: String) -> Self {
        changing(name: name, module: module, mainFile: mainFile, triple: target, modified: modified)
    }

    /// This unit compiled for module `module` (a C99 name).
    func inModule(_ module: String) -> Self {
        changing(name: name, module: module, mainFile: mainFile, triple: target, modified: modified)
    }

    /// This unit with main file `mainFile`.
    func atFile(_ mainFile: String) -> Self {
        changing(name: name, module: module, mainFile: mainFile, triple: target, modified: modified)
    }

    /// This unit compiled for target triple `triple`.
    func forTriple(_ triple: String) -> Self {
        changing(name: name, module: module, mainFile: mainFile, triple: triple, modified: modified)
    }

    /// This unit modified at `modified`.
    func modifiedAt(_ modified: ModificationDate) -> Self {
        changing(name: name, module: module, mainFile: mainFile, triple: target, modified: modified)
    }

    /// This unit naming the records `names` (sorted, as the store lists
    /// them).
    func writing(_ names: [String]) -> Self {
        IndexUnitFact(
            name: name,
            module: module,
            mainFile: mainFile,
            target: target,
            isSystem: isSystem,
            modified: modified,
            records: names.sorted(),
            moduleDependencies: moduleDependencies
        )
    }

    /// This unit with the fields given, its system flag, records and module
    /// dependencies kept.
    private func changing(
        name: String,
        module: String,
        mainFile: String,
        triple: String,
        modified: ModificationDate
    ) -> Self {
        IndexUnitFact(
            name: name,
            module: module,
            mainFile: mainFile,
            target: triple,
            isSystem: isSystem,
            modified: modified,
            records: records,
            moduleDependencies: moduleDependencies
        )
    }
}

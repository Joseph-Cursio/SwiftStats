//
//  IndexUnitFact+Changes.swift
//  SwiftStatsCoreTests
//
//  Copies of a recorded unit with one field changed, for injecting units
//  beside a recording in the unit filter's and the index walk's tests (M7,
//  design §2.3).
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

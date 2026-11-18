//
//  RollupInput.swift
//  SwiftStatsCore
//
//  Everything a roll-up counts, for the whole scan or narrowed to some
//  modules.
//

/// The scan's facts that roll-ups count.
struct RollupInput {
    /// Function records.
    var records: [FunctionRecord]
    /// Type records.
    var types: [TypeRecord]
    /// File records.
    var files: [FileRecord]
    /// Declarations the API surface counts.
    var declarations: [APIDeclaration]
    /// Findings, with the tools that ran; narrowed by file when counted.
    var findings: FindingTally

    /// These facts for `modules` only.
    func narrowed(to modules: Set<String>) -> Self {
        Self(
            records: records.filter { modules.contains($0.module) },
            types: types.filter { modules.contains($0.module) },
            files: files.filter { modules.contains($0.module) },
            declarations: declarations.filter { modules.contains($0.module) },
            findings: findings
        )
    }
}

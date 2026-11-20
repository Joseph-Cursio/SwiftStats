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
    /// The test inventory.
    var tests: [TestRecord]
    /// Findings, with the tools that ran; narrowed by file when counted.
    var findings: FindingTally
    /// Whether SwiftEffectInference ran, so production scopes count effects.
    var effectsCollected: Bool
    /// Law checks per production conformance.
    var laws: [LawCheck]
    /// SwiftInferProperties' suggestions; nil when it didn't run. Its
    /// candidates are narrowed by file when counted, like findings.
    var properties: PropertyReport?
    /// SwiftCloneDetector's classes and the lines they cover; nil when it
    /// didn't run. Counted by file, like findings.
    var clones: CloneMapping?

    /// These facts for `modules` only.
    func narrowed(to modules: Set<String>) -> Self {
        Self(
            records: records.filter { modules.contains($0.module) },
            types: types.filter { modules.contains($0.module) },
            files: files.filter { modules.contains($0.module) },
            declarations: declarations.filter { modules.contains($0.module) },
            tests: tests.filter { modules.contains($0.module) },
            findings: findings,
            effectsCollected: effectsCollected,
            laws: laws.filter { modules.contains($0.module) },
            properties: properties,
            clones: clones
        )
    }
}

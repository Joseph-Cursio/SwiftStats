//
//  ScanMeasurements.swift
//  SwiftStatsCore
//
//  What SwiftStats measures from the parsed trees, before the external
//  tools' findings are added.
//

/// SwiftStats' own measurements of a package.
struct ScanMeasurements {
    /// Function records, keys resolved and scores joined; side effects are
    /// joined after measuring.
    var records: [FunctionRecord]
    /// Type records.
    let types: [TypeRecord]
    /// File records.
    let files: [FileRecord]
    /// Declarations the API surface counts.
    let declarations: [APIDeclaration]
    /// SwiftStats' own markers.
    let markers: [RawFinding]
    /// Each file's top-level statement lines, by path.
    let topLevelLines: [String: Set<Int>]
    /// Each file's `private` and `fileprivate` types, as dotted paths, by path.
    let fileScopedTypes: [String: Set<String>]
    /// The test inventory.
    let tests: [TestRecord]
    /// The base names each property test calls, by test key.
    let propertyCallees: [String: Set<String>]
    /// The test-target files whose leading comments carry a
    /// SwiftInferProperties suggestion identity, by identity.
    let stubs: [String: Set<String>]
    /// The law each `@CheckProperty` the macro accepts checks, by the
    /// place its marker names.
    let checkProperties: [RawFinding.Place: CheckPropertyKind]
    /// Law checks per production conformance; `kitDependency` is set when
    /// the report is assembled, from the package's dependencies.
    let laws: LawReport
    /// Each parsed file with its module.
    let parsed: [(module: String, file: ParsedFile)]
    /// Sitrep-compatible counts.
    let sitrep: SitrepReport
    /// The complexity definition behind the scores.
    let metrics: MetricsInfo
    /// Problems found while measuring.
    let warnings: [ScanWarning]
    /// Whether SwiftEffectInference ran, so `records` carry side effects
    /// and production roll-ups count them.
    var effectsCollected = false
}

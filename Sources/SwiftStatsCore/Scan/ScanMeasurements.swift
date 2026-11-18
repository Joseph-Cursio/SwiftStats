//
//  ScanMeasurements.swift
//  SwiftStatsCore
//
//  What SwiftStats measures from the parsed trees, before the external
//  tools' findings are added.
//

/// SwiftStats' own measurements of a package.
struct ScanMeasurements {
    /// Function records, keys resolved and scores joined.
    let records: [FunctionRecord]
    /// Type records.
    let types: [TypeRecord]
    /// File records.
    let files: [FileRecord]
    /// Declarations the API surface counts.
    let declarations: [APIDeclaration]
    /// SwiftStats' own risk markers.
    let markers: [RawFinding]
    /// Each parsed file with its module.
    let parsed: [(module: String, file: ParsedFile)]
    /// Sitrep-compatible counts.
    let sitrep: SitrepReport
    /// The complexity definition behind the scores.
    let metrics: MetricsInfo
    /// Problems found while measuring.
    let warnings: [ScanWarning]
}

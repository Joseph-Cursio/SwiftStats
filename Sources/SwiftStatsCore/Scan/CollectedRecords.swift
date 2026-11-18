//
//  CollectedRecords.swift
//  SwiftStatsCore
//
//  What one walk over the parsed files yields, before keys are resolved and
//  scores attached.
//

/// The function, type and file records of a scan, in walk order.
struct CollectedRecords {
    /// Function records.
    var records: [FunctionRecord] = []
    /// Type records.
    var types: [TypeRecord] = []
    /// File records.
    var files: [FileRecord] = []
    /// Declarations the API surface counts.
    var declarations: [APIDeclaration] = []
    /// SwiftStats' own risk markers.
    var markers: [RawFinding] = []
    /// Each file's top-level statement lines, by path.
    var topLevelLines: [String: Set<Int>] = [:]
}

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
}

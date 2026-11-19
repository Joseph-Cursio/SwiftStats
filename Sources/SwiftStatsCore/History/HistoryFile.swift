//
//  HistoryFile.swift
//  SwiftStatsCore
//
//  One parsed version of one Swift file: its function rows and body line hashes.
//

/// One version of one file, parsed.
struct HistoryFile: Sendable {
    /// Its function records, as store rows.
    let rows: [FunctionRow]
    /// Each record's body as hashes of its normalised lines, sorted and
    /// unique, by key; only for bodies of three lines or more.
    let lines: [String: [UInt64]]
}

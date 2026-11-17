//
//  RecordAddress.swift
//  SwiftStatsCore
//
//  A key within one file: enough to re-point children at a parent whose key
//  was disambiguated.
//

/// A record's original key and file.
struct RecordAddress: Hashable {
    /// The file, relative to the package root.
    let file: String
    /// The key before disambiguation.
    let key: String
}

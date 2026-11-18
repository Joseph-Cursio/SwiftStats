//
//  RawFinding.swift
//  SwiftStatsCore
//
//  A tool's result before it is attached to records.
//

/// A tool's result with its places not yet attached.
struct RawFinding: Hashable {
    /// A place a raw finding names.
    struct Place: Hashable {
        /// Path relative to the package root.
        let file: String
        /// 1-based line.
        let line: Int
        /// 1-based column, when the tool gives one.
        let column: Int?
    }

    let tool: String
    let rule: String
    let category: String?
    let kind: FindingKind
    let severity: String
    let message: String
    let symbol: String?
    let places: [Place]
}

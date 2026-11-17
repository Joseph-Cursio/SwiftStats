//
//  SitrepFileFacts.swift
//  SwiftStatsCore
//
//  What Sitrep's aggregate counts need from one file.
//

/// One file's contribution to the Sitrep counts.
struct SitrepFileFacts: Equatable {
    /// The file path, relative to the package root.
    let path: String
    /// Number of `\n` bytes in the file.
    let newlineCount: Int
    /// Number of non-empty lines (a line of spaces is not empty).
    let nonEmptyLineCount: Int
    /// The types Sitrep treats as top-level, in source order.
    let types: [SitrepTypeFact]
    /// Each import's module path as written, in source order.
    let imports: [String]
}

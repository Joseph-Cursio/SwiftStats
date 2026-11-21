//
//  CoverageFileLines.swift
//  SwiftStatsCore
//
//  A kept file's line coverage (M5): every mapped line's count by
//  llvm-cov's file line rule, the same lines `llvm-cov export -format=lcov`
//  gives, and the ranges an inactive `#if` skips. Scope totals, markers
//  and clone copies read these.
//

/// One kept file's line data.
public struct CoverageFileLines: Codable, Hashable, Sendable {
    /// Path of the file, relative to the package root.
    public let file: String
    /// Its mapped lines, in runs of one count, by line.
    public let lines: [CoverageLineRun]
    /// The lines skipped regions cover, sorted.
    public let skipped: [CoverageLineRange]

    /// Creates a file's lines. Fields are documented on their properties.
    public init(file: String, lines: [CoverageLineRun], skipped: [CoverageLineRange]) {
        self.file = file
        self.lines = lines
        self.skipped = skipped
    }
}

//
//  CoverageExportFile.swift
//  SwiftStatsCore
//
//  A file of llvm-cov's export (M5): its absolute real path and its
//  segments, in order. Branches, expansions, MC/DC records and the summary
//  aren't read: Swift emits none of the first three, and the summary
//  counts a closure's lines twice.
//

/// A file of the export.
struct CoverageExportFile: Decodable, Hashable, Sendable {
    /// The keys read.
    private enum CodingKeys: String, CodingKey {
        case filename, segments
    }

    /// The absolute real path.
    let filename: String
    /// Its segments, by position.
    let segments: [CoverageSegment]
}

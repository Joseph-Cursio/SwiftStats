//
//  CoverageExportFile.swift
//  SwiftStatsCore
//
//  A file of llvm-cov's export (M5): its absolute real path and its
//  segments, in order. Branches, expansions, MC/DC records and the summary
//  aren't read: Swift emits none of the first three, and the summary
//  counts a closure's lines twice. llvm's segment builder writes a file's
//  segments sorted by line, then column, two sharing a position only
//  when the first carries no count; the export's decoder rejects a file
//  whose segments go back (design B3, decided U6), since the line rule
//  walks them in order.
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

    /// The first two adjacent segments whose second lies before the first
    /// by line, then column; nil when the segments are sorted. Segments
    /// sharing a position are in order.
    var misordered: (earlier: CoverageSegment, later: CoverageSegment)? {
        zip(segments, segments.dropFirst())
            .first { pair in (pair.1.line, pair.1.column) < (pair.0.line, pair.0.column) }
            .map { (earlier: $0.0, later: $0.1) }
    }
}

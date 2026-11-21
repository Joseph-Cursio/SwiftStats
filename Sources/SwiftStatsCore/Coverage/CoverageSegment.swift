//
//  CoverageSegment.swift
//  SwiftStatsCore
//
//  A coverage segment (M5): from its position on, until the next segment,
//  code ran `executionCount` times, as llvm's segments say it. A file's come
//  from the export, `[line, column, count, hasCount, isRegionEntry,
//  isGapRegion]`; a record's are built from its regions by
//  `CoverageSegmentBuilder`.
//

/// One coverage segment.
struct CoverageSegment: Decodable, Hashable, Sendable {
    /// Its line.
    let line: Int
    /// Its column.
    let column: Int
    /// The count from here on; 0 when it has none.
    let executionCount: Int64
    /// Whether it carries a count: false where code ends, or a skipped
    /// region starts.
    let hasCount: Bool
    /// Whether a region starts here.
    let isRegionEntry: Bool
    /// Whether it starts a gap region.
    let isGapRegion: Bool

    /// Whether a counted region starts here, as llvm's line rule asks.
    var startsRegion: Bool {
        isGapRegion == false && hasCount && isRegionEntry
    }

    /// Creates a segment. Fields are documented on their properties.
    init(line: Int, column: Int, executionCount: Int64, hasCount: Bool, isRegionEntry: Bool, isGapRegion: Bool) {
        self.line = line
        self.column = column
        self.executionCount = executionCount
        self.hasCount = hasCount
        self.isRegionEntry = isRegionEntry
        self.isGapRegion = isGapRegion
    }

    /// Decodes the six-element array.
    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        line = try container.decode(Int.self)
        column = try container.decode(Int.self)
        executionCount = try CoverageCount.decode(from: &container)
        hasCount = try container.decode(Bool.self)
        isRegionEntry = try container.decode(Bool.self)
        isGapRegion = try container.decode(Bool.self)
    }
}

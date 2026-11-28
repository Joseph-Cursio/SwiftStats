//
//  CoverageLineIterator.swift
//  SwiftStatsCore
//
//  llvm-cov's line rule, as `LineCoverageStats` and `LineCoverageIterator`
//  (`CoverageMapping.cpp`) apply it to segments (M5). Each line from the
//  first segment's to the last's is mapped when no skipped region starts
//  it and a counted segment wraps into it or a counted region starts on
//  it; its count is the wrapping segment's, raised by the counts of the
//  regions starting on it. Over a file's segments this gives llvm-cov's
//  file view (the lines `-format=lcov` lists); over a record's own, its
//  per-function figures. Segments come sorted by line, then column: the
//  export's decoder rejects a file whose segments aren't (design B3,
//  decided U6), and `CoverageSegmentBuilder` builds a record's in order
//  from well-formed regions. The walk steps over a gap no counted segment
//  wraps, whose lines are all unmapped, so its time doesn't grow with the
//  gap; a segment on an earlier line than the walk has reached ends it.
//

/// llvm-cov's line rule.
enum CoverageLineIterator {
    /// A mapped line.
    struct Line: Hashable, Sendable {
        /// The line number.
        let line: Int
        /// Its count; `Int64.max` when saturated.
        let executionCount: Int64
        /// Whether it ran but a region starting on it didn't.
        let partlyRun: Bool

        /// Whether it ran at least once.
        var ran: Bool {
            executionCount > 0
        }
    }

    /// The mapped lines of `segments`, which are sorted by line, then
    /// column. After a line, the walk goes on to the next line when the
    /// last segment so far carries a count (it wraps into that line), and
    /// otherwise straight to the next segment's line, since no line in
    /// between is mapped. It stops at a segment on an earlier line than it
    /// has reached, and after line `Int.max`, as no later line can exist.
    static func lines(of segments: [CoverageSegment]) -> [Line] {
        guard var line = segments.first?.line else {
            return []
        }
        var result: [Line] = []
        var wrapped: CoverageSegment?
        var next = 0
        while next < segments.count {
            var current: [CoverageSegment] = []
            while next < segments.count, segments[next].line == line {
                current.append(segments[next])
                next += 1
            }
            if let mapped = stats(of: current, wrapped: wrapped, line: line) {
                result.append(mapped)
            }
            wrapped = current.last ?? wrapped
            guard next < segments.count, segments[next].line > line else {
                break
            }
            line = wrapped?.hasCount == true ? line + 1 : segments[next].line
        }
        return result
    }

    /// `line`, holding the segments `starting` there, with `wrapped` the
    /// last segment of the latest earlier line that has any; nil when it
    /// isn't mapped.
    private static func stats(of starting: [CoverageSegment], wrapped: CoverageSegment?, line: Int) -> Line? {
        let regionStarts = starting.filter(\.startsRegion)
        let startsSkipped = starting.first.map { $0.hasCount == false && $0.isRegionEntry } ?? false
        let isMapped = (startsSkipped == false && (wrapped?.hasCount == true || regionStarts.isEmpty == false))
            || starting.contains { $0.isRegionEntry && $0.hasCount }
        guard isMapped else {
            return nil
        }
        let executions = regionStarts.map(\.executionCount).reduce(wrapped?.executionCount ?? 0, max)
        return Line(
            line: line,
            executionCount: executions,
            partlyRun: executions > 0 && regionStarts.contains { $0.executionCount <= 0 }
        )
    }
}

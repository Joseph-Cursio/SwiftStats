//
//  SegmentListDraft.swift
//  SwiftStatsCoreTests
//
//  A list of coverage segments as decisions, for P2.1: each segment's
//  step from the one before (lines down, then columns along), its flags
//  and count; where the lines start (at line 1, at or below 0, at
//  `Int.min`, or ending on `Int.max`); and, for a list in no order, one
//  segment moved. The interpreter keeps the segments sorted by line, then
//  column, before the move, two sharing a position when a step is 0. A
//  step past `CoverageGen.gapCap` is taken only after a segment with no
//  count, in a list nothing is moved in: a counted segment wraps every line
//  up to the next, and the line rule maps each of them (design D7 caps
//  such gaps); a gap no count wraps maps none of its lines, so it may be as
//  long as any.
//

@testable import SwiftStatsCore

/// A list of coverage segments as decisions.
struct SegmentListDraft: Hashable, Sendable {
    /// Where a list's lines start.
    enum Anchor: Hashable, Sendable {
        /// Its last segment is on `Int.max`.
        case end
        /// Its first segment is on this line.
        case start(Int)
    }

    /// One segment as decisions.
    struct Segment: Hashable, Sendable {
        /// How many lines after the segment before it this one is.
        let lineStep: Int
        /// How many columns after the one before it on its line, or after
        /// column 1 on a new line.
        let columnStep: Int
        /// Whether it carries a count.
        let hasCount: Bool
        /// Whether a region starts here.
        let isRegionEntry: Bool
        /// Whether it starts a gap region.
        let isGapRegion: Bool
        /// Its count.
        let executionCount: Int64
    }

    /// A segment moved, by indices taken modulo the list's length.
    struct Move: Hashable, Sendable {
        /// The index it is taken from.
        let source: Int
        /// The index it is put at.
        let target: Int
    }

    /// The segments, in order.
    let segments: [Segment]
    /// Where their lines start.
    let anchor: Anchor
    /// The segment moved, if any.
    let move: Move?

    /// The segments the decisions make.
    var built: [CoverageSegment] {
        var steps = segments.map(\.lineStep)
        for index in steps.indices where steps[index] > CoverageGen.gapCap {
            let afterUncounted = index > 0 && segments[index - 1].hasCount == false
            if move != nil || afterUncounted == false {
                steps[index] = CoverageGen.gapCap
            }
        }
        let offsets = steps.indices.map { index in index == 0 ? 0 : steps[1...index].reduce(0, +) }
        let first: Int
        switch anchor {
        case .end:
            first = Int.max - (offsets.last ?? 0)

        case .start(let line):
            first = line
        }
        var sorted: [CoverageSegment] = []
        for (index, segment) in segments.enumerated() {
            let line = first + offsets[index]
            let sameLine = index > 0 && steps[index] == 0
            let column = (sameLine ? sorted[index - 1].column : 1) + segment.columnStep
            sorted.append(CoverageSegment(
                line: line,
                column: column,
                executionCount: segment.executionCount,
                hasCount: segment.hasCount,
                isRegionEntry: segment.isRegionEntry,
                isGapRegion: segment.isGapRegion
            ))
        }
        guard let move, sorted.isEmpty == false else {
            return sorted
        }
        let moved = sorted.remove(at: move.source % sorted.count)
        sorted.insert(moved, at: move.target % (sorted.count + 1))
        return sorted
    }
}

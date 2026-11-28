//
//  CoverageGen.swift
//  SwiftStatsCoreTests
//
//  Coverage segments for P2.1, and mapped lines for P2.4. Segment lists
//  are drawn as decisions (`SegmentListDraft`): flags in every
//  combination, so skipped starts, counted and uncounted entries, gaps and
//  resumed counts all come up, counts of 0, small, saturated, and below 0
//  (which llvm never writes but the export's decoder reads as spelled,
//  P2.6), and
//  lines that share a segment's line, follow it, or lie past a gap of up
//  to 1,000 lines (design D7, assumed), or past a gap of any length that
//  no count wraps; their lines start at 1, at or below 0, at `Int.min`,
//  or end on `Int.max`. A list is sorted by line, then column, or has one
//  segment moved, so a walk meets a segment on an earlier line; or it is
//  the segments `CoverageSegmentBuilder` builds from generated regions
//  (`CoverageRegionGen`), as a record's are. Mapped lines, for runs, come
//  in increasing order, most next to the line before, with counts and
//  partly-run flags drawn so neighbours often agree; partly run only on a
//  line that ran, as the line rule says.
//

import PropertyBased
@testable import SwiftStatsCore

/// Generators of coverage segments and mapped lines.
enum CoverageGen {
    /// The longest gap a counted segment wraps (design D7, assumed: past
    /// any function body; the line rule maps each of its lines).
    static let gapCap = 1_000
    /// The longest gap no count wraps (assumed: far past any file, and far
    /// past what a walk over each line could cover in a run).
    static let hugeGap = 1_000_000_000_000
    /// How many segments a list has (design D7).
    static let segmentCount = 0...24
    /// How many lines a list of mapped lines has (design D7).
    static let lineCount = 0...30
    /// The largest small count (assumed: enough to differ, and to tie).
    static let smallCount: Int64 = 9
    /// The largest column step (assumed: enough to share, and to order).
    static let columnStep = 0...3
    /// A short step between lines.
    static let shortStep = 2...4
    /// A long step between lines, up to the gap cap.
    static let longStep = 5...gapCap
    /// A step only an uncounted segment may take before it.
    static let hugeStep = (gapCap + 1)...hugeGap
    /// The largest index a move draws, taken modulo the list's length.
    static let largestIndex = 99
    /// The lowest line at or below 0 a list may start on (assumed).
    static let lowestStart = -3
    /// Lines at or below 0 a list may start on.
    static let lowStart = lowestStart...0
    /// The smallest count above 1.
    static let smallestOfSmall: Int64 = 2
    /// Counts below 0 a segment may carry: llvm never writes them, but the
    /// export's decoder reads them as spelled (P2.6).
    static let negativeCounts: [Int64] = [-1, Int64.min]

    /// Weight of a step of no line or of one line.
    static let nearWeight = 3.0
    /// Weight of a short step.
    static let shortWeight = 2.0
    /// Weight of each other class.
    static let classWeight = 1.0
    /// Weight of starting on line 1.
    static let firstLineWeight = 4.0
    /// Weight of a count of 0.
    static let zeroWeight = 3.0
    /// Weight of a count of 1, or of a small count.
    static let lowWeight = 2.0
    /// Weight of a sorted list drawn as decisions, in P2.1's input.
    static let sortedWeight = 3.0
    /// Weight of a list with a segment moved.
    static let movedWeight = 1.0
    /// Weight of a list built from regions.
    static let builtWeight = 2.0
    /// Weight of a line next to the line before, among mapped lines.
    static let adjacentWeight = 6.0
    /// The share of segments with a count.
    static let countedRate: Float = 0.75
    /// The share of segments entering a region.
    static let entryRate: Float = 0.6
    /// The share of segments starting a gap region.
    static let gapRate: Float = 0.2
    /// The share of lines that ran marked partly run.
    static let partlyRunRate: Float = 0.3

    /// A count: 0, 1, small, or saturated.
    static let count = Gen.frequency(
        (zeroWeight, Gen.always(Int64.zero)),
        (lowWeight, Gen.always(Int64(1))),
        (lowWeight, Gen<Int64>.value(in: smallestOfSmall...smallCount)),
        (classWeight, Gen.always(Int64.max))
    )

    /// A segment's count: one of `count`'s, or below 0.
    static let segmentExecutionCount = Gen.frequency(
        (zeroWeight, Gen.always(Int64.zero)),
        (lowWeight, Gen.always(Int64(1))),
        (lowWeight, Gen<Int64>.value(in: smallestOfSmall...smallCount)),
        (classWeight, Gen.always(Int64.max)),
        (classWeight, Pick.element(of: negativeCounts))
    )

    /// A step between lines: none, one, short, long, or huge.
    static let lineStep = Gen.frequency(
        (nearWeight, Gen<Int>.value(in: 0...1)),
        (shortWeight, Gen<Int>.value(in: shortStep)),
        (classWeight, Gen<Int>.value(in: longStep)),
        (classWeight, Gen<Int>.value(in: hugeStep))
    )

    /// One segment.
    static let segment = zip(
        lineStep,
        Gen<Int>.value(in: columnStep),
        Gen.bool(countedRate),
        Gen.bool(entryRate),
        Gen.bool(gapRate),
        segmentExecutionCount
    )
    .map(SegmentListDraft.Segment.init)

    /// Where a list's lines start.
    static let anchor = Gen.frequency(
        (firstLineWeight, Gen.always(SegmentListDraft.Anchor.start(1))),
        (classWeight, Gen<Int>.value(in: lowStart).map(SegmentListDraft.Anchor.start)),
        (classWeight, Gen.always(SegmentListDraft.Anchor.start(Int.min))),
        (classWeight, Gen.always(SegmentListDraft.Anchor.end))
    )

    /// A segment moved.
    static let move = zip(Gen<Int>.value(in: 0...largestIndex), Gen<Int>.value(in: 0...largestIndex))
        .map(SegmentListDraft.Move.init)

    /// A list sorted by line, then column.
    static let sortedList = zip(segment.array(of: segmentCount), anchor)
        .map { segments, anchor in SegmentListDraft(segments: segments, anchor: anchor, move: nil) }

    /// A list with one segment moved, in no order.
    static let movedList = zip(segment.array(of: segmentCount), anchor, move)
        .map(SegmentListDraft.init)

    /// P2.1's input: a sorted list, a list with a segment moved, or the
    /// segments built from generated regions.
    static let segments = Gen.frequency(
        (sortedWeight, sortedList.map(GeneratedSegments.Source.drafted)),
        (movedWeight, movedList.map(GeneratedSegments.Source.drafted)),
        (builtWeight, CoverageRegionGen.regions.map(GeneratedSegments.Source.built))
    )
    .map(GeneratedSegments.init)
    .eraseToAny()

    /// A step between mapped lines: most often the next line.
    static let mappedStep = Gen.frequency(
        (adjacentWeight, Gen.always(1)),
        (shortWeight, Gen<Int>.value(in: shortStep)),
        (classWeight, Gen<Int>.value(in: longStep))
    )

    /// One mapped line as decisions: its step, count and partly-run flag.
    static let mappedLine = zip(mappedStep, count, Gen.bool(partlyRunRate))
        .map(MappedLinesDraft.Line.init)

    /// P2.4's input: mapped lines in increasing order.
    static let lines = zip(mappedLine.array(of: lineCount), anchor)
        .map(MappedLinesDraft.init)
        .eraseToAny()
}

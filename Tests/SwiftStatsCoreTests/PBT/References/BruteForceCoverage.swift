//
//  BruteForceCoverage.swift
//  SwiftStatsCoreTests
//
//  The references P2.1 and P2.2 compare SwiftStats' port of llvm's
//  coverage rules with, written from what llvm documents of those rules
//  (`CoverageMapping.h`'s comments on `CoverageSegment`,
//  `LineCoverageStats`, `LineCoverageIterator` and the segment builder's
//  sort, which `CoverageLineIterator` and `CoverageSegmentBuilder` cite)
//  and from PRD §7.8, not from SwiftStats' code (design D12). Each answers
//  one point or one line at a time, with no walk:
//  - A segment gives a count from its position until the next segment
//    (llvm: "the execution count information starting at a point"); one
//    without a count gives none. So the count at a position is the last
//    segment's at or before it.
//  - Regions are half-open, their end column exclusive; the count at a
//    position is the innermost region's holding it (the latest start, then
//    the earliest end), none in a skipped region or outside every region.
//    Regions of one range count as the first in kind order (code,
//    expansion, skipped, gap: llvm's sort comment "prefer CodeRegion to
//    ExpansionRegion and ExpansionRegion to SkippedRegion"), with the
//    largest count among those of its kind (PRD §7.8: counts are "only
//    compared, never summed").
//  - Line rule: a line's segments are those starting on it; its wrapped
//    segment is the last segment of the latest earlier line that has any;
//    a region starts on it where a segment enters a region, has a count
//    and isn't a gap. It is mapped when a counted segment enters a region
//    on it, and otherwise unless its first segment starts a skipped region
//    (enters one with no count), when its wrapped segment has a count or a
//    region starts on it. Its count is its wrapped segment's, raised to
//    the largest count of the regions starting on it. The lines run from
//    the first segment's to the last's. It is partly run (PRD §7.8: "a
//    line that ran while holding a region-entry segment that didn't") when
//    its count is above 0 and a region starting on it has a count at or
//    below 0: a line ran when its count is above 0, and the decoder reads
//    a negative count as spelled, though llvm never writes one.
//  - The walk reads segments sorted by line, and ends at a segment on an
//    earlier line than it has reached (`CoverageLineIterator.lines(of:)`'s
//    doc comment, design B3): so over any list the rule applies to the
//    longest prefix whose lines never go back.
//  - Flags: a region starting at a position is innermost there when it
//    ends earliest, then comes first in kind order; P2.2's flag laws read
//    a segment's entry, gap and count flags from that region and from the
//    innermost region holding the segment's position (llvm's segment
//    builder comments, and `CoverageSegmentBuilder`'s header, quoted where
//    the laws are).
//

@testable import SwiftStatsCore

/// Coverage rules as llvm documents them, answered one point or one line
/// at a time.
enum BruteForceCoverage {
    /// The longest prefix of `segments` whose lines never go back: what the
    /// walk reads of them.
    static func walkedPrefix(of segments: [CoverageSegment]) -> ArraySlice<CoverageSegment> {
        let back = segments.indices.dropFirst().first { segments[$0].line < segments[$0 - 1].line }
        return back.map { segments[..<$0] } ?? segments[...]
    }

    /// The lines the line rule maps over `segments`, read as the walk
    /// reads them (`walkedPrefix(of:)`), in order. Only lines that can be
    /// mapped are judged: a line holding a segment, or one after the last
    /// segment of an earlier line when that segment has a count. Any other
    /// line has no segment, so no region starts or is entered on it, and
    /// its wrapped segment has no count: the rule maps none of them.
    static func lineRule(of segments: [CoverageSegment]) -> [CoverageLineIterator.Line] {
        let walked = Array(walkedPrefix(of: segments))
        let byLine = Dictionary(grouping: walked, by: \.line)
        let lines = byLine.keys.sorted()
        var result: [CoverageLineIterator.Line] = []
        for (index, line) in lines.enumerated() {
            let starting = byLine[line] ?? []
            let wrapped = index > 0 ? byLine[lines[index - 1]]?.last : nil
            if let mapped = rule(line: line, starting: starting, wrapped: wrapped) {
                result.append(mapped)
            }
            guard let last = starting.last, last.hasCount, index + 1 < lines.count, line + 1 < lines[index + 1] else {
                continue
            }
            for between in (line + 1)..<lines[index + 1] {
                if let mapped = rule(line: between, starting: [], wrapped: last) {
                    result.append(mapped)
                }
            }
        }
        return result
    }

    /// What the line rule says of `line`, where `starting` are the
    /// segments on it, in order, and `wrapped` its wrapped segment; nil
    /// when it isn't mapped.
    static func rule(
        line: Int,
        starting: [CoverageSegment],
        wrapped: CoverageSegment?
    ) -> CoverageLineIterator.Line? {
        let regionStarts = starting.filter { $0.isRegionEntry && $0.hasCount && $0.isGapRegion == false }
        let entersCounted = starting.contains { $0.isRegionEntry && $0.hasCount }
        let startsSkipped = starting.first.map { $0.isRegionEntry && $0.hasCount == false } ?? false
        let wrapsCounted = wrapped?.hasCount ?? false
        let mapped = entersCounted || (startsSkipped == false && (wrapsCounted || regionStarts.isEmpty == false))
        guard mapped else {
            return nil
        }
        var count = wrapped?.executionCount ?? 0
        for region in regionStarts where region.executionCount > count {
            count = region.executionCount
        }
        let partlyRun = count > 0 && regionStarts.contains { $0.executionCount <= 0 }
        return CoverageLineIterator.Line(line: line, executionCount: count, partlyRun: partlyRun)
    }

    /// The count `segments`, sorted by position, give `position`: the last
    /// segment's at or before it; nil before the first, or where that
    /// segment has no count.
    static func count(at position: SourcePosition, segments: [CoverageSegment]) -> Int64? {
        let giving = segments.last { SourcePosition(line: $0.line, column: $0.column) <= position }
        guard let giving, giving.hasCount else {
            return nil
        }
        return giving.executionCount
    }

    /// The count `regions` give `position`: the innermost region's holding
    /// it, those of its range counted as the first in kind order with the
    /// largest count of that kind; nil when no region holds it or that
    /// region is skipped.
    static func count(at position: SourcePosition, regions: [CoverageRegion]) -> Int64? {
        let innermost = innermostRange(holding: position, regions: regions)
        guard let kind = innermost.map(\.kind).min(), kind != CoverageRegion.skippedKind else {
            return nil
        }
        return innermost.filter { $0.kind == kind }.map(\.executionCount).max()
    }

    /// The innermost region holding `position`: of those holding it, the
    /// latest start, then the earliest end, then the first in kind order;
    /// nil when no region holds it. An empty region holds no position.
    static func innermostRegion(holding position: SourcePosition, regions: [CoverageRegion]) -> CoverageRegion? {
        firstInKindOrder(innermostRange(holding: position, regions: regions))
    }

    /// The innermost region starting at `position`: of those starting
    /// there, the earliest end, then the first in kind order; nil when none
    /// starts there.
    static func innermostRegion(starting position: SourcePosition, regions: [CoverageRegion]) -> CoverageRegion? {
        let starting = regions.filter { $0.start == position }
        guard let end = starting.map(\.end).min() else {
            return nil
        }
        return firstInKindOrder(starting.filter { $0.end == end })
    }

    /// The regions holding `position` with the latest start, then the
    /// earliest end: one range, of any kinds.
    private static func innermostRange(
        holding position: SourcePosition,
        regions: [CoverageRegion]
    ) -> [CoverageRegion] {
        let holding = regions.filter { $0.start <= position && position < $0.end }
        guard let start = holding.map(\.start).max() else {
            return []
        }
        let latest = holding.filter { $0.start == start }
        guard let end = latest.map(\.end).min() else {
            return []
        }
        return latest.filter { $0.end == end }
    }

    /// The first of `regions`, one range, in kind order.
    private static func firstInKindOrder(_ regions: [CoverageRegion]) -> CoverageRegion? {
        regions.min { $0.kind < $1.kind }
    }
}

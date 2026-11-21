//
//  CoverageSegmentBuilder.swift
//  SwiftStatsCore
//
//  Builds segments from regions as llvm's `SegmentBuilder` does
//  (`CoverageMapping.cpp`), so a record's lines follow llvm-cov's own
//  per-function rule (M5): regions sorted outermost first, those of one
//  range combined, then a segment where each region starts and, where an
//  inner region ends, one resuming the region around it; after the last
//  region a segment without a count. Regions of one range keep the largest
//  count, never a sum (llvm sums them; a record's are deduplicated first,
//  so they never meet).
//

/// llvm's segment builder.
struct CoverageSegmentBuilder {
    /// The segments built so far.
    private var segments: [CoverageSegment] = []
    /// The regions open at the current position, outermost first.
    private var active: [CoverageRegion] = []

    /// The segments of `regions`, in order.
    static func segments(of regions: [CoverageRegion]) -> [CoverageSegment] {
        var builder = Self()
        builder.build(combined(regions.sorted(by: nestedOrder)))
        return builder.segments
    }

    /// By start; of one start, the longer first; of one range, code before
    /// expansion before skipped.
    private static func nestedOrder(_ lhs: CoverageRegion, _ rhs: CoverageRegion) -> Bool {
        if lhs.start != rhs.start {
            return lhs.start < rhs.start
        }
        if lhs.end != rhs.end {
            return rhs.end < lhs.end
        }
        return lhs.kind < rhs.kind
    }

    /// `sorted` with the regions of one range combined into the first, its
    /// count the largest of those of its kind.
    private static func combined(_ sorted: [CoverageRegion]) -> [CoverageRegion] {
        var result: [CoverageRegion] = []
        for region in sorted {
            if let last = result.last, last.start == region.start, last.end == region.end {
                if last.kind == region.kind, region.executionCount > last.executionCount {
                    result[result.count - 1] = last.with(executionCount: region.executionCount)
                }
                continue
            }
            result.append(region)
        }
        return result
    }

    /// Adds a segment at `position` with `region`'s count, unless it would
    /// change nothing; `skipped` makes it a segment without a count.
    private mutating func startSegment(
        _ region: CoverageRegion,
        at position: SourcePosition,
        isRegionEntry: Bool,
        skipped: Bool
    ) {
        let hasCount = skipped == false && region.isSkipped == false
        if let last = segments.last, isRegionEntry == false, skipped == false,
           last.hasCount == hasCount, last.executionCount == region.executionCount, last.isRegionEntry == false {
            return
        }
        segments.append(CoverageSegment(
            line: position.line,
            column: position.column,
            executionCount: hasCount ? region.executionCount : 0,
            hasCount: hasCount,
            isRegionEntry: isRegionEntry,
            isGapRegion: hasCount && region.kind == CoverageRegion.gapKind
        ))
    }

    /// Closes the active regions from `firstCompleted` on, all of which end
    /// at or before `next`, the start of the next region (nil after the
    /// last), adding the segments where each ends.
    private mutating func complete(until next: SourcePosition?, firstCompleted: Int) {
        let completed = active[firstCompleted...].enumerated()
            .sorted { ($0.element.end, $0.offset) < ($1.element.end, $1.offset) }
            .map(\.element)
        active = Array(active[..<firstCompleted]) + completed
        var index = firstCompleted + 1
        while index < active.count {
            var region = active[index]
            let position = active[index - 1].end
            if let next, position == next {
                break
            }
            if position != region.end {
                // The count of the last completed region ending here.
                for later in active[(index + 1)...] where later.end == region.end {
                    region = later
                }
                startSegment(region, at: position, isRegionEntry: false, skipped: false)
            }
            index += 1
        }
        if let last = active.last {
            if firstCompleted > 0, last.end != next {
                startSegment(active[firstCompleted - 1], at: last.end, isRegionEntry: false, skipped: false)
            } else if firstCompleted == 0, next.map({ $0 != last.end }) ?? true {
                startSegment(last, at: last.end, isRegionEntry: false, skipped: true)
            }
        }
        active.removeSubrange(firstCompleted...)
    }

    /// Builds the segments of `regions`, sorted and combined.
    private mutating func build(_ regions: [CoverageRegion]) {
        for (index, region) in regions.enumerated() {
            let start = region.start
            let open = active.filter { ($0.end <= start) == false }
            let ended = active.filter { $0.end <= start }
            if ended.isEmpty == false {
                active = open + ended
                complete(until: start, firstCompleted: open.count)
            }
            let isLast = index + 1 == regions.count
            let isGap = region.kind == CoverageRegion.gapKind
            if start == region.end {
                // An empty region never becomes active.
                let skipped = isLast || region.isSkipped
                startSegment(active.last ?? region, at: start, isRegionEntry: isGap == false, skipped: skipped)
                if skipped, let enclosing = active.last {
                    startSegment(enclosing, at: start, isRegionEntry: false, skipped: false)
                }
                continue
            }
            if isLast || start != regions[index + 1].start {
                startSegment(region, at: start, isRegionEntry: isGap == false, skipped: false)
            }
            active.append(region)
        }
        if active.isEmpty == false {
            complete(until: nil, firstCompleted: 0)
        }
    }
}

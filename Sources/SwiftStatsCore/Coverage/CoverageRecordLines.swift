//
//  CoverageRecordLines.swift
//  SwiftStatsCore
//
//  A record's line and region figures (M5). Its regions are its entries'
//  code regions deduplicated by range with the largest count, covered when
//  the count is above 0. Its lines follow llvm-cov's per-function rule:
//  segments built from those regions and its skipped ones, the line rule
//  run over them, then each line dropped that lies in a nested record's
//  span and on which none of its own regions starts. So sibling accessors
//  on one line each get the line, an unrun nested function reads 0, and a
//  closure's lines count for its parent with the closure's counts.
//

/// Line and region figures of one record.
enum CoverageRecordLines {
    /// `regions` with those of one range merged into one with the largest
    /// count, by start, then end.
    static func deduplicated(_ regions: [CoverageRegion]) -> [CoverageRegion] {
        var byRange: [SourceSpan: CoverageRegion] = [:]
        for region in regions {
            let range = SourceSpan(start: region.start, end: region.end)
            if let kept = byRange[range], kept.executionCount >= region.executionCount {
                continue
            }
            byRange[range] = region
        }
        return byRange.values.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    /// The covered and total of `regions`.
    static func tally(of regions: [CoverageRegion]) -> CoverageTally {
        CoverageTally(covered: regions.count(where: \.ran), total: regions.count)
    }

    /// The lines of a record whose deduplicated code regions are `regions`
    /// and skipped regions `skipped`, with `nested` the spans of the
    /// records nested in it.
    static func lines(
        regions: [CoverageRegion],
        skipped: [CoverageRegion],
        nested: [Set<Int>]
    ) -> [CoverageLineIterator.Line] {
        let starts = Set(regions.map(\.start.line))
        return CoverageLineIterator.lines(of: CoverageSegmentBuilder.segments(of: regions + skipped)).filter { line in
            starts.contains(line.line) || nested.contains { $0.contains(line.line) } == false
        }
    }

    /// The covered and total of `lines`.
    static func tally(of lines: [CoverageLineIterator.Line]) -> CoverageTally {
        CoverageTally(covered: lines.count(where: \.ran), total: lines.count)
    }
}

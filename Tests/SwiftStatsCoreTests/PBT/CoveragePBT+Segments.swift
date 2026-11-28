//
//  CoveragePBT+Segments.swift
//  SwiftStatsCoreTests
//
//  P2.2: the segments `CoverageSegmentBuilder` builds from well-nested
//  regions are sorted and give every point the count of the innermost
//  region holding it, half-open at the end; an empty region takes its
//  enclosing region's count. Empty regions no region holds are left out
//  of the domain: llvm's builder gives such a region its own count until
//  the next region starts, a quirk `unheldEmptyRegion` pins without the
//  law. The segments' entry, gap and count flags follow the laws in
//  `CoveragePBT+Flags.swift`. The kind-first rule for identical ranges of
//  different kinds is pinned by an example.
//

import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P2.2.
extension CoveragePBT {
    /// P2.2's base runs, over the engine's 100 (a grid of a few hundred
    /// points, each answered by both sides, costs about a millisecond): the
    /// rarest antecedent, an empty region in a skipped region, comes in 126
    /// of the meta-test's 1,000 lists (design D14: `(1 - 0.126)^110`, about
    /// 4 * 10^-7, is the most a run misses it; 100 runs would miss it about
    /// 1.4 * 10^-6 of the time); a point between regions comes in 159.
    static let pointwiseRuns = 110
    /// What P2.2's tally counts when a region is empty.
    static let emptyRegion = "an empty region"
    /// What it counts when two regions share a range.
    static let repeatedRange = "a range held twice"
    /// What it counts when a point's innermost region is skipped.
    static let skippedPoint = "a point in a skipped region"
    /// What it counts when a point's innermost region is a gap.
    static let gapPoint = "a point in a gap region"
    /// What it counts when no region holds a point between two that do.
    static let uncoveredPoint = "a point between regions"
    /// What it counts when an empty region starts where the last region
    /// starts, so its entry has no count (a flag law's antecedent).
    static let emptyLast = "an empty region starting last"
    /// What it counts when an empty region lies in a skipped region, so
    /// its entry has no count (a flag law's antecedent).
    static let emptyInSkipped = "an empty region in a skipped region"
    /// What it counts when the innermost region starting somewhere is a
    /// gap, so no segment enters a region there (a flag law's antecedent).
    static let gapStart = "a start whose innermost region is a gap"
    /// The antecedents P2.2 must reach at least once each.
    static let pointwiseAntecedents = [
        emptyRegion, repeatedRange, skippedPoint, gapPoint, uncoveredPoint, emptyLast, emptyInSkipped, gapStart
    ]

    /// `segment`'s position.
    static func position(of segment: CoverageSegment) -> SourcePosition {
        SourcePosition(line: segment.line, column: segment.column)
    }

    /// Every position from the first line any of `regions` touches to the
    /// line after the last, at every column up to one past the widest.
    static func grid(of regions: [CoverageRegion]) -> [SourcePosition] {
        let lines = regions.flatMap { [$0.start.line, $0.end.line] }
        guard let low = lines.min(), let high = lines.max(),
              let wide = regions.flatMap({ [$0.start.column, $0.end.column] }).max() else {
            return []
        }
        return (low...(high + 1)).flatMap { line in
            (1...(wide + 1)).map { SourcePosition(line: line, column: $0) }
        }
    }

    /// The classes `regions` fall in, for P2.2's tally and the generator's
    /// meta-test.
    static func pointwiseLabels(of regions: [CoverageRegion]) -> [String] {
        let ranges = regions.map { SourceSpan(start: $0.start, end: $0.end) }
        let innermost = grid(of: regions).map { position in
            regions.filter { $0.start <= position && position < $0.end }
                .max { ($0.start, $1.end) < ($1.start, $0.end) }
        }
        let first = regions.map(\.start).min()
        let last = regions.map(\.end).max()
        let positions = grid(of: regions)
        let between = zip(positions, innermost).contains { position, region in
            region == nil && first.map { $0 < position } == true && last.map { position < $0 } == true
        }
        let empties = regions.filter { $0.start == $0.end }
        let lastStart = regions.map(\.start).max()
        let gapStarts = Set(regions.map(\.start)).contains { start in
            BruteForceCoverage.innermostRegion(starting: start, regions: regions)?.kind == CoverageRegion.gapKind
        }
        let emptiesInSkipped = empties.contains { empty in
            BruteForceCoverage.innermostRegion(holding: empty.start, regions: regions)?.isSkipped == true
        }
        return [
            (empties.isEmpty == false, emptyRegion),
            (Set(ranges).count < ranges.count, repeatedRange),
            (innermost.contains { $0?.isSkipped == true }, skippedPoint),
            (innermost.contains { $0?.kind == CoverageRegion.gapKind }, gapPoint),
            (between, uncoveredPoint),
            (empties.contains { $0.start == lastStart }, emptyLast),
            (emptiesInSkipped, emptyInSkipped),
            (gapStarts, gapStart)
        ]
        .filter(\.0)
        .map(\.1)
    }

    /// Whether `segments`, what the builder built from `regions`, are
    /// sorted by position (two sharing one only when the first carries no
    /// count, as llvm's builder asserts) and give every point of the grid
    /// the count the innermost region holding it has (`BruteForceCoverage`).
    /// Records an issue for each law that fails.
    static func checkPointwise(_ regions: [CoverageRegion], segments: [CoverageSegment]) -> Bool {
        let unsorted = zip(segments, segments.dropFirst()).first { earlier, later in
            position(of: later) < position(of: earlier)
                || (position(of: later) == position(of: earlier) && earlier.hasCount)
        }
        let wrong = grid(of: regions).first { position in
            BruteForceCoverage.count(at: position, segments: segments)
                != BruteForceCoverage.count(at: position, regions: regions)
        }
        let shownWrong = wrong.map { position in
            let given = BruteForceCoverage.count(at: position, segments: segments).map { "\($0)" } ?? "none"
            let held = BruteForceCoverage.count(at: position, regions: regions).map { "\($0)" } ?? "none"
            return "gives \(position.line):\(position.column) count \(given), where the innermost region gives \(held)"
        }
        let shownUnsorted = unsorted.map { pair in
            "puts \(GeneratedSegments.shown(pair.1)) after \(GeneratedSegments.shown(pair.0))"
        }
        return holds(
            [(unsorted == nil, shownUnsorted ?? ""), (wrong == nil, shownWrong ?? "")],
            subject: "the segments of \(regions.count) regions"
        )
    }

    /// A region of `kind` from `start` to `end`, exclusive, with `count`.
    static func region(_ start: (Int, Int), _ end: (Int, Int), _ count: Int64, kind: Int) -> CoverageRegion {
        CoverageRegion(
            start: SourcePosition(line: start.0, column: start.1),
            end: SourcePosition(line: end.0, column: end.1),
            executionCount: count,
            fileID: 0,
            expandedFileID: 0,
            kind: kind
        )
    }

    /// `segment` with `count`.
    static func counted(_ segment: CoverageSegment, _ count: Int64) -> CoverageSegment {
        CoverageSegment(
            line: segment.line,
            column: segment.column,
            executionCount: count,
            hasCount: segment.hasCount,
            isRegionEntry: segment.isRegionEntry,
            isGapRegion: segment.isGapRegion
        )
    }

    // MARK: P2.2

    /// Invariant: for well-nested regions, one kind per identical range,
    /// the built segments are sorted and give each (line, column) the
    /// count of the innermost region holding it, half-open at the end;
    /// none in a skipped region or outside every region; an empty region
    /// takes its enclosing region's count. Their flags follow the builder's
    /// header: entries exactly at the starts of regions other than gaps, a
    /// gap flag exactly where the innermost region is a gap, and no count
    /// on an entry into a skipped region or an empty one that comes last
    /// or lies in a skipped region (`checkFlags`).
    /// Why it holds: `CoverageSegmentBuilder`'s header (llvm's
    /// `SegmentBuilder`: a segment where each region starts, one resuming
    /// the enclosing region where an inner one ends, one without a count
    /// after the last), `CoverageSegment`'s ("from its position on, until
    /// the next segment"), `CoverageRegion`'s (the end column exclusive).
    /// Why it might not: identical ranges of different kinds follow the
    /// kind-first rule, pinned by an example, not drawn; an empty region no
    /// region holds is left out, since llvm's builder gives it its own count
    /// until the next region starts (a quirk, pinned by
    /// `unheldEmptyRegion`); positions are at most `CoverageRegionGen.width`
    /// columns to a line (assumed).
    /// Oracle: reference (`BruteForceCoverage`, a grid scan, and its
    /// innermost regions for the flags); planted defects: no resuming
    /// segment, regions of one range summed, an empty region starting its
    /// own count, and the end column inclusive, each detected, and for the
    /// flags every counted segment a gap, an entry cleared, a resuming
    /// segment entered, and an empty last region's entry counted.
    /// Tier: Strict (stop-ship).
    @Test(
        "the segments of well-nested regions give each point the innermost region's count, half-open at the end",
        .timeLimit(PBTBudget.timeLimit)
    )
    func segmentsGiveInnermostCounts() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.pointwiseRuns), input: CoverageRegionGen.regions) { input in
            PBTTrace.note(input)
            let regions = input.regions
            Self.pointwiseLabels(of: regions).forEach(tally.fire)
            let segments = CoverageSegmentBuilder.segments(of: regions)
            let pointwise = Self.checkPointwise(regions, segments: segments)
            if (Self.checkFlags(regions, segments: segments) && pointwise) == false {
                PBTTrace.firstFailure(input, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.pointwiseAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("each recorded function entry's regions build segments giving every point its innermost region's count")
    func recordedEntriesGiveInnermostCounts() throws {
        let entries = try Self.recordedData().map(CoverageExport.decode).flatMap(\.functions)

        #expect(entries.count == 140)
        for entry in entries {
            let regions = entry.regions.filter { $0.fileID == 0 }
            let segments = CoverageSegmentBuilder.segments(of: regions)

            #expect(Self.checkPointwise(regions, segments: segments))
            #expect(Self.checkFlags(regions, segments: segments))
        }
    }

    @Test("""
        identical ranges of different kinds, given in either order, count as the first in kind order, the largest \
        count of that kind: code over gap, code over skipped, skipped over gap
        """)
    func kindFirstRule() {
        let codeOverGap = [
            Self.region((1, 1), (3, 1), 9, kind: CoverageRegion.gapKind),
            Self.region((1, 1), (3, 1), 1, kind: CoverageRegion.codeKind),
            Self.region((1, 1), (3, 1), 5, kind: CoverageRegion.codeKind)
        ]
        let codeOverSkipped = [
            Self.region((1, 1), (3, 1), 4, kind: CoverageRegion.codeKind),
            Self.region((1, 1), (3, 1), 0, kind: CoverageRegion.skippedKind)
        ]
        let skippedOverGap = [
            Self.region((1, 1), (5, 1), 4, kind: CoverageRegion.codeKind),
            Self.region((2, 1), (3, 1), 9, kind: CoverageRegion.gapKind),
            Self.region((2, 1), (3, 1), 0, kind: CoverageRegion.skippedKind)
        ]

        for regions in [codeOverGap, codeOverSkipped, skippedOverGap] {
            for ordered in [regions, Array(regions.reversed())] {
                let segments = CoverageSegmentBuilder.segments(of: ordered)

                #expect(Self.checkPointwise(ordered, segments: segments))
                #expect(Self.checkFlags(ordered, segments: segments))
            }
        }
        for ordered in [codeOverGap, Array(codeOverGap.reversed())] {
            let codeSegments = CoverageSegmentBuilder.segments(of: ordered)

            #expect(codeSegments.first?.executionCount == 5)
            #expect(codeSegments.first?.isGapRegion == false)
        }
        let skippedSegments = CoverageSegmentBuilder.segments(of: skippedOverGap)
        #expect(BruteForceCoverage.count(at: SourcePosition(line: 2, column: 4), segments: skippedSegments) == nil)
    }

    @Test("an empty region takes its enclosing region's count, and one with no enclosing region gives none")
    func emptyRegions() {
        let regions = [
            Self.region((1, 1), (2, 3), 3, kind: CoverageRegion.codeKind),
            Self.region((1, 4), (1, 4), 0, kind: CoverageRegion.codeKind),
            Self.region((2, 3), (2, 3), 7, kind: CoverageRegion.codeKind)
        ]

        let segments = CoverageSegmentBuilder.segments(of: regions)

        #expect(Self.checkPointwise(regions, segments: segments))
        #expect(BruteForceCoverage.count(at: SourcePosition(line: 1, column: 4), segments: segments) == 3)
        #expect(BruteForceCoverage.count(at: SourcePosition(line: 2, column: 3), segments: segments) == nil)
    }

    @Test("""
        an empty region no region holds gives its own count until the next region starts, as llvm's builder does, \
        so the lines between map though no region holds them; last, it gives none
        """)
    func unheldEmptyRegion() {
        // A pin of llvm's behaviour outside P2.2's domain: it doesn't call
        // `checkPointwise`, whose law fails on the leading case.
        let leading = [
            Self.region((1, 3), (1, 3), 5, kind: CoverageRegion.codeKind),
            Self.region((3, 1), (4, 1), 1, kind: CoverageRegion.codeKind)
        ]
        let trailing = [
            Self.region((1, 1), (2, 1), 1, kind: CoverageRegion.codeKind),
            Self.region((3, 2), (3, 2), 5, kind: CoverageRegion.codeKind)
        ]

        let segments = CoverageSegmentBuilder.segments(of: leading)
        let lines = CoverageLineIterator.lines(of: segments)
        let trailingSegments = CoverageSegmentBuilder.segments(of: trailing)
        let trailingLines = CoverageLineIterator.lines(of: trailingSegments)

        #expect(BruteForceCoverage.count(at: SourcePosition(line: 2, column: 1), segments: segments) == 5)
        #expect(BruteForceCoverage.count(at: SourcePosition(line: 2, column: 1), regions: leading) == nil)
        #expect(lines.map(Self.shown) == ["1:5", "2:5", "3:5", "4:1"])
        #expect(trailingLines.map(Self.shown) == ["1:1", "2:1"])
        #expect(BruteForceCoverage.count(at: SourcePosition(line: 3, column: 2), segments: trailingSegments) == nil)
    }

    @Test("a planted defect's segments fail P2.2's law")
    func pointwiseDefectsDetected() {
        let regions = [
            Self.region((1, 1), (3, 1), 4, kind: CoverageRegion.codeKind),
            Self.region((1, 3), (2, 2), 1, kind: CoverageRegion.codeKind),
            Self.region((1, 3), (2, 2), 2, kind: CoverageRegion.codeKind),
            Self.region((2, 3), (2, 3), 0, kind: CoverageRegion.codeKind)
        ]
        let segments = CoverageSegmentBuilder.segments(of: regions)
        let unresumed = segments.filter { $0.isRegionEntry || $0.hasCount == false }
        let summed = segments.map { segment in
            segment.line == 1 && segment.column == 3 ? Self.counted(segment, 3) : segment
        }
        let emptyOwnCount = segments.map { segment in
            segment.line == 2 && segment.column == 3 ? Self.counted(segment, 0) : segment
        }
        let endInclusive = segments.map { segment in
            segment.isRegionEntry
                ? segment
                : CoverageSegment(
                    line: segment.line,
                    column: segment.column + 1,
                    executionCount: segment.executionCount,
                    hasCount: segment.hasCount,
                    isRegionEntry: false,
                    isGapRegion: segment.isGapRegion
                )
        }

        #expect(Self.checkPointwise(regions, segments: segments))
        PlantedDefect.expectDetected("no segment resuming the enclosing region", sourceLocation: #_sourceLocation) {
            Self.checkPointwise(regions, segments: unresumed)
        }
        PlantedDefect.expectDetected("regions of one range summed", sourceLocation: #_sourceLocation) {
            Self.checkPointwise(regions, segments: summed)
        }
        PlantedDefect.expectDetected("an empty region giving its own count", sourceLocation: #_sourceLocation) {
            Self.checkPointwise(regions, segments: emptyOwnCount)
        }
        PlantedDefect.expectDetected("the end column inclusive", sourceLocation: #_sourceLocation) {
            Self.checkPointwise(regions, segments: endInclusive)
        }
    }
}

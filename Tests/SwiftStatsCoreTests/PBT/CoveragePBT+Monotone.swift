//
//  CoveragePBT+Monotone.swift
//  SwiftStatsCoreTests
//
//  P2.3: over the segments `CoverageSegmentBuilder` builds from
//  well-nested regions, raising one region's count never lowers the count
//  of a line it leaves mapped, adding a skipped region never adds a mapped
//  line, and a line no region touches is never mapped. A raise can map or
//  unmap a line: llvm's builder leaves out a segment that repeats the
//  count before it, and whether a line's first segment starts a skipped
//  region can turn on that (`raiseMovesTheFirstSegment` pins it).
//

import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P2.3.
extension CoveragePBT {
    /// P2.3's base runs, over the engine's 100: three builds and walks of
    /// up to 30 regions cost well under a millisecond, and the rarest
    /// antecedent, a line no region touches between regions, comes in 87
    /// of the meta-test's 1,000 changes (design D14: `(1 - 0.087)^160`,
    /// about 5 * 10^-7, is the most a run misses it; 100 runs would miss it
    /// about 10^-4 of the time).
    static let monotoneRuns = 160
    /// What P2.3's tally counts when raising a count raised a line's.
    static let raisedLine = "a raised count raising a line's"
    /// What it counts when leaving out the skipped region maps a line.
    static let skippedHides = "a skipped region hiding a line"
    /// What it counts when a line no region touches lies between the
    /// first line a region touches and the last.
    static let untouchedLine = "a line no region touches between regions"
    /// The antecedents P2.3 must reach at least once each.
    static let monotoneAntecedents = [raisedLine, skippedHides, untouchedLine]

    /// The lines some region of `regions` touches: from its start's line
    /// to its end's.
    static func touchedLines(of regions: [CoverageRegion]) -> Set<Int> {
        Set(regions.flatMap { $0.start.line <= $0.end.line ? Array($0.start.line...$0.end.line) : [] })
    }

    /// The classes of `change`, whose lines are `base`, `raised` with the
    /// count raised and `withoutSkipped` with the skipped region left out,
    /// for P2.3's tally and the generator's meta-test.
    static func monotoneLabels(
        of change: RegionChange,
        base: [CoverageLineIterator.Line],
        raised: [CoverageLineIterator.Line],
        withoutSkipped: [CoverageLineIterator.Line]
    ) -> [String] {
        let touched = touchedLines(of: change.regions)
        let untouched = touched.min().map { low in
            (low...(touched.max() ?? low)).contains { touched.contains($0) == false }
        }
        let before = Dictionary(uniqueKeysWithValues: base.map { ($0.line, $0.executionCount) })
        return [
            (raised.contains { line in before[line.line].map { $0 < line.executionCount } ?? false }, raisedLine),
            (Set(withoutSkipped.map(\.line)).isSubset(of: base.map(\.line)) == false, skippedHides),
            (untouched == true, untouchedLine)
        ]
        .filter(\.0)
        .map(\.1)
    }

    /// Whether `base`, the lines of `regions`, `raised`, those
    /// with one count raised, and `withoutSkipped`, those with one skipped
    /// region left out, change only as the line rule allows: no line
    /// mapped before and after the raise has a lower count after it; every
    /// line mapped with the skipped region is mapped without it; and every
    /// mapped line is one a region touches. Records an issue for each law
    /// that fails.
    static func checkMonotone(
        _ regions: [CoverageRegion],
        base: [CoverageLineIterator.Line],
        raised: [CoverageLineIterator.Line],
        withoutSkipped: [CoverageLineIterator.Line]
    ) -> Bool {
        let after = Dictionary(uniqueKeysWithValues: raised.map { ($0.line, $0.executionCount) })
        let lowered = base.first { line in after[line.line].map { $0 < line.executionCount } ?? false }
        let added = Set(base.map(\.line)).subtracting(withoutSkipped.map(\.line)).min()
        let touched = touchedLines(of: regions)
        let stray = base.first { touched.contains($0.line) == false }
        return holds(
            [
                (lowered == nil, lowered.map { "lowers line \($0.line) from \($0.executionCount)" } ?? ""),
                (added == nil, added.map { "maps line \($0) only with the skipped region" } ?? ""),
                (stray == nil, stray.map { "maps line \($0.line), which no region touches" } ?? "")
            ],
            subject: "the lines of \(regions.count) regions"
        )
    }

    // MARK: P2.3

    /// Invariant: raising one region's count never lowers the count of a
    /// line it leaves mapped; adding a skipped region never adds a mapped
    /// line; a line no region touches is unmapped.
    /// Why it holds: `CoverageLineIterator`'s header (a line is mapped by
    /// counted segments wrapping into it or regions starting on it, never
    /// by a count's size; its count is the largest of those; a skipped
    /// region's start unmaps its line) and `CoverageSegmentBuilder`'s (a
    /// segment without a count after the last region, and between regions).
    /// Why it might not: the regions are well nested with one kind per
    /// identical range, as P2.2's, and none is empty: llvm's builder makes
    /// an empty region that comes last a skipped start, and one before
    /// another region a counted entry, so adding a region after it can map
    /// its line (pinned by an example). Leaving out a skipped region keeps
    /// the regions so. A raise may map or unmap a line (llvm leaves out a
    /// segment repeating the count before it, which can decide whether a
    /// line's first segment starts a skipped region; pinned by an example),
    /// so the law compares only lines mapped both before and after.
    /// Oracle: metamorphic; planted defects: the builder's uncounted
    /// segment after a top-level region dropped, a raise lowering a line, a
    /// skipped region mapping a line it holds, and a line between regions
    /// mapped, each detected.
    /// Tier: Strict (stop-ship).
    @Test(
        """
        raising a count never lowers a line it leaves mapped, adding a skipped region maps no line, and a line no \
        region touches stays unmapped
        """,
        .timeLimit(PBTBudget.timeLimit)
    )
    func linesMoveOneWay() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.monotoneRuns), input: CoverageRegionGen.change) { change in
            PBTTrace.note(change)
            let base = CoverageLineIterator.lines(of: CoverageSegmentBuilder.segments(of: change.regions))
            let raised = CoverageLineIterator.lines(of: CoverageSegmentBuilder.segments(of: change.raisedRegions))
            let without = CoverageLineIterator.lines(of: CoverageSegmentBuilder.segments(of: change.withoutSkipped))
            Self.monotoneLabels(of: change, base: base, raised: raised, withoutSkipped: without).forEach(tally.fire)
            if Self.checkMonotone(change.regions, base: base, raised: raised, withoutSkipped: without) == false {
                PBTTrace.firstFailure(change, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.monotoneAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("""
        a skipped region at the start of a line unmaps it, raising the body's count raises every line it wraps, \
        and the lines between two functions stay unmapped
        """)
    func skippedStartAndRaise() {
        let draft = RegionListDraft(
            steps: [
                .open(kind: CoverageRegion.codeKind, count: 1), .advance(4),
                .open(kind: CoverageRegion.skippedKind, count: 0),
                .advance(3), .close, .advance(5), .close, .advance(12),
                .open(kind: CoverageRegion.codeKind, count: 2), .advance(5)
            ],
            reversed: false
        )
        let change = RegionChange(draft: draft, raisedIndex: 1, raise: nil, removedIndex: 0)

        let base = CoverageLineIterator.lines(of: CoverageSegmentBuilder.segments(of: change.regions))
        let raised = CoverageLineIterator.lines(of: CoverageSegmentBuilder.segments(of: change.raisedRegions))
        let without = CoverageLineIterator.lines(of: CoverageSegmentBuilder.segments(of: change.withoutSkipped))

        #expect(Self.checkMonotone(change.regions, base: base, raised: raised, withoutSkipped: without))
        #expect(base.map(\.line) == [1, 3, 4, 7, 8])
        #expect(without.map(\.line) == [1, 2, 3, 4, 7, 8])
        #expect(raised.map(\.executionCount) == [Int64.max, Int64.max, Int64.max, 2, 2])
    }

    @Test("""
        an empty region that comes last is a skipped start, unmapping its line, and a skipped region added after it \
        makes it a counted entry, mapping the line, as llvm's builder does
        """)
    func emptyRegionComingLast() {
        let enclosing = Self.region((1, 1), (1, 3), 1, kind: CoverageRegion.gapKind)
        let empty = Self.region((1, 1), (1, 1), 1, kind: CoverageRegion.codeKind)
        let skipped = Self.region((1, 2), (1, 3), 0, kind: CoverageRegion.skippedKind)

        let alone = CoverageLineIterator.lines(of: CoverageSegmentBuilder.segments(of: [enclosing, empty]))
        let added = CoverageLineIterator.lines(of: CoverageSegmentBuilder.segments(of: [enclosing, empty, skipped]))

        #expect(alone.isEmpty)
        #expect(added.map(Self.shown) == ["1:0"])
    }

    @Test("""
        raising an inner gap's count to its enclosing gap's drops its segment, so a skipped region starts the line \
        and unmaps it; raising it past that maps the line again, as llvm's builder does
        """)
    func raiseMovesTheFirstSegment() {
        let regions = [
            Self.region((1, 1), (3, 2), 3, kind: CoverageRegion.gapKind),
            Self.region((2, 1), (3, 2), 1, kind: CoverageRegion.gapKind),
            Self.region((2, 2), (3, 2), 0, kind: CoverageRegion.skippedKind)
        ]
        var level = regions
        var past = regions
        level[1] = regions[1].with(executionCount: 3)
        past[1] = regions[1].with(executionCount: Int64.max)

        let base = CoverageLineIterator.lines(of: CoverageSegmentBuilder.segments(of: regions))
        let leveled = CoverageLineIterator.lines(of: CoverageSegmentBuilder.segments(of: level))
        let raised = CoverageLineIterator.lines(of: CoverageSegmentBuilder.segments(of: past))

        #expect(base.map(Self.shown) == ["2:3"])
        #expect(leveled.isEmpty)
        #expect(raised.map(Self.shown) == ["2:3"])
        #expect(Self.checkMonotone(regions, base: base, raised: leveled, withoutSkipped: base))
    }

    @Test("a planted defect's lines fail P2.3's law")
    func monotoneDefectsDetected() {
        let regions = [
            Self.region((1, 1), (4, 1), 1, kind: CoverageRegion.codeKind),
            Self.region((2, 1), (2, 4), 0, kind: CoverageRegion.skippedKind),
            Self.region((7, 1), (8, 2), 2, kind: CoverageRegion.codeKind)
        ]
        let base = CoverageLineIterator.lines(of: CoverageSegmentBuilder.segments(of: regions))
        let without = CoverageLineIterator.lines(of: CoverageSegmentBuilder.segments(of: Array(regions.dropFirst(2))))
        var lowered = base
        lowered[0] = CoverageLineIterator.Line(line: 1, executionCount: 0, partlyRun: false)
        let skippedMapsLine = base.filter { $0.line != 3 }
        let untouched = base + [CoverageLineIterator.Line(line: 9, executionCount: 2, partlyRun: false)]

        #expect(base.map(Self.shown) == ["1:1", "3:1", "4:1", "7:2", "8:2"])
        #expect(Self.checkMonotone(regions, base: base, raised: base, withoutSkipped: base))
        #expect(without.map(Self.shown) == ["7:2", "8:2"])
        PlantedDefect.expectDetected("a raise lowering a line", sourceLocation: #_sourceLocation) {
            Self.checkMonotone(regions, base: base, raised: lowered, withoutSkipped: base)
        }
        PlantedDefect.expectDetected("a skipped region mapping a line", sourceLocation: #_sourceLocation) {
            Self.checkMonotone(regions, base: base, raised: base, withoutSkipped: skippedMapsLine)
        }
        PlantedDefect.expectDetected("a line no region touches mapped", sourceLocation: #_sourceLocation) {
            Self.checkMonotone(regions, base: untouched, raised: untouched, withoutSkipped: untouched)
        }
    }
}

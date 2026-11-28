@testable import SwiftStatsCore
import Testing

/// llvm-cov's segment builder and line rule, ported (M5): the segments a
/// record's regions give, the lines they map, and a record's lines with
/// those of the records nested in it dropped; a gap no counted segment
/// wraps is stepped over, and a backward segment ends the walk.
@Suite("Coverage line rule")
struct CoverageLineRuleTests {
    /// Lines in the gap of `unwrappedGap`: before the walk stepped over a
    /// gap no counted segment wraps, it visited each of them, about 0.23 µs
    /// a line in a debug build (1e9 took 227 s); these 2e7 took 4.5 s.
    private static let unwrappedGapLines = 20_000_000
    /// The most the walk over that gap may take.
    private static let walkBound = Duration.seconds(1)

    /// The fixture's `outer(_:)`: a run body, an `if` whose then-branch
    /// didn't run and whose else-branch did.
    private static let outer = [
        Self.code((2, 40), (11, 2), 1),
        Self.code((6, 8), (6, 12), 1),
        Self.code((6, 13), (8, 6), 0),
        Self.code((8, 12), (10, 6), 1)
    ]

    /// A code region from `start` to `end` (exclusive) that ran `count` times.
    private static func code(_ start: (Int, Int), _ end: (Int, Int), _ count: Int64) -> CoverageRegion {
        region(start, end, count, kind: CoverageRegion.codeKind)
    }

    /// A skipped region from `start` to `end`.
    private static func skipped(_ start: (Int, Int), _ end: (Int, Int)) -> CoverageRegion {
        region(start, end, 0, kind: CoverageRegion.skippedKind)
    }

    /// A region of `kind`.
    private static func region(_ start: (Int, Int), _ end: (Int, Int), _ count: Int64, kind: Int) -> CoverageRegion {
        CoverageRegion(
            start: SourcePosition(line: start.0, column: start.1),
            end: SourcePosition(line: end.0, column: end.1),
            executionCount: count,
            fileID: 0,
            expandedFileID: 0,
            kind: kind
        )
    }

    /// A segment: `[line, column, count, hasCount, isRegionEntry]`, never a gap.
    private static func segment(_ line: Int, _ column: Int, _ count: Int64, _ hasCount: Bool, _ entry: Bool)
        -> CoverageSegment {
        CoverageSegment(
            line: line,
            column: column,
            executionCount: count,
            hasCount: hasCount,
            isRegionEntry: entry,
            isGapRegion: false
        )
    }

    @Test("llvm's segment builder: an inner region's end resumes the outer count, and the last ends uncounted")
    func outerSegments() {
        let segments = CoverageSegmentBuilder.segments(of: Self.outer)

        #expect(segments == [
            Self.segment(2, 40, 1, true, true),
            Self.segment(6, 8, 1, true, true),
            Self.segment(6, 12, 1, true, false),
            Self.segment(6, 13, 0, true, true),
            Self.segment(8, 6, 1, true, false),
            Self.segment(8, 12, 1, true, true),
            Self.segment(10, 6, 1, true, false),
            Self.segment(11, 2, 0, false, false)
        ])
    }

    @Test("the line rule maps lines a segment wraps into or starts on, takes the largest count, flags partly run ones")
    func lineRule() {
        let lines = CoverageLineIterator.lines(of: CoverageSegmentBuilder.segments(of: Self.outer))

        #expect(lines.map(\.line) == Array(2...11))
        #expect(lines.map(\.executionCount) == [1, 1, 1, 1, 1, 0, 1, 1, 1, 1])
        #expect(lines.filter(\.partlyRun).map(\.line) == [6])
    }

    @Test("skipped regions in a body leave their lines unmapped, the #else line included, as llvm-cov reports")
    func skippedLines() {
        let regions = [
            Self.code((20, 34), (26, 2), 1),
            Self.skipped((21, 5), (23, 10)),
            Self.skipped((25, 5), (25, 11))
        ]

        let lines = CoverageLineIterator.lines(of: CoverageSegmentBuilder.segments(of: regions))

        #expect(lines.map(\.line) == [20, 24, 26])
        #expect(lines.allSatisfy { $0.executionCount == 1 && $0.partlyRun == false })
    }

    @Test("regions of one range keep the largest count, never a sum, in segments and in a record's regions")
    func sameRange() {
        let twins = [
            Self.code((35, 46), (37, 2), 1),
            Self.code((36, 21), (36, 25), 1),
            Self.code((36, 21), (36, 25), 2)
        ]

        let segments = CoverageSegmentBuilder.segments(of: twins)
        let regions = CoverageRecordLines.deduplicated(twins)

        #expect(segments.first { $0.line == 36 && $0.column == 21 }?.executionCount == 2)
        #expect(regions.map(\.executionCount) == [1, 2])
        #expect(CoverageRecordLines.tally(of: regions) == CoverageTally(covered: 2, total: 2))
    }

    @Test("an empty region never becomes active: it takes its enclosing count, and the enclosing one goes on")
    func emptyRegion() {
        let regions = [Self.code((1, 10), (3, 2), 4), Self.code((2, 5), (2, 5), 0), Self.code((2, 9), (2, 12), 0)]

        let segments = CoverageSegmentBuilder.segments(of: regions)

        #expect(segments == [
            Self.segment(1, 10, 4, true, true),
            Self.segment(2, 5, 4, true, true),
            Self.segment(2, 9, 0, true, true),
            Self.segment(2, 12, 4, true, false),
            Self.segment(3, 2, 0, false, false)
        ])
    }

    @Test("a record's lines drop a nested record's wrap-only lines, but keep a line one of its regions starts on")
    func nestedLines() {
        let parent = CoverageRecordLines.lines(regions: Self.outer, skipped: [], nested: [Set(3...5)])
        let sameLine = CoverageRecordLines.lines(
            regions: [Self.code((14, 31), (14, 68), 1)],
            skipped: [],
            nested: [[14]]
        )
        let unrunNested = CoverageRecordLines.lines(regions: [Self.code((3, 37), (5, 6), 0)], skipped: [], nested: [])

        #expect(parent.map(\.line) == [2, 6, 7, 8, 9, 10, 11])
        #expect(CoverageRecordLines.tally(of: parent) == CoverageTally(covered: 6, total: 7))
        #expect(sameLine.map(\.line) == [14])
        #expect(CoverageRecordLines.tally(of: unrunNested) == CoverageTally(covered: 0, total: 3))
    }

    @Test("a file's lines come in runs of one count and one partly-run flag")
    func runs() {
        let lines = CoverageLineIterator.lines(of: CoverageSegmentBuilder.segments(of: Self.outer))

        #expect(CoverageFileRuns.runs(of: lines) == [
            CoverageLineRun(start: 2, end: 5, count: 1, partlyRun: false),
            CoverageLineRun(start: 6, end: 6, count: 1, partlyRun: true),
            CoverageLineRun(start: 7, end: 7, count: 0, partlyRun: false),
            CoverageLineRun(start: 8, end: 11, count: 1, partlyRun: false)
        ])
    }

    @Test("a gap no counted segment wraps maps none of its lines, and the walk steps over it in well under a second")
    func unwrappedGap() {
        let resumed = 4 + Self.unwrappedGapLines
        let segments = [
            Self.segment(1, 1, 1, true, true),
            Self.segment(3, 2, 0, false, false),
            Self.segment(resumed, 1, 2, true, true),
            Self.segment(resumed + 1, 2, 0, false, false)
        ]
        var lines: [CoverageLineIterator.Line] = []

        let elapsed = ContinuousClock().measure {
            lines = CoverageLineIterator.lines(of: segments)
        }

        #expect(lines.map(\.line) == [1, 2, 3, resumed, resumed + 1])
        #expect(lines.map(\.executionCount) == [1, 1, 1, 2, 2])
        #expect(elapsed < Self.walkBound)
    }

    @Test("a gap a counted segment wraps maps every line of it with that count, as llvm's rule does")
    func wrappedGap() {
        let segments = [Self.segment(1, 1, 3, true, true), Self.segment(6, 2, 0, false, false)]

        let lines = CoverageLineIterator.lines(of: segments)

        #expect(lines.map(\.line) == Array(1...6))
        #expect(lines.allSatisfy { $0.executionCount == 3 })
    }

    @Test("a segment on an earlier line than the walk has reached ends the walk there")
    func backwardSegment() {
        let segments = [
            Self.segment(Int.max - 10, 1, 1, true, true),
            Self.segment(Int.max - 20, 1, 5, true, true),
            Self.segment(Int.max, 1, 0, false, false)
        ]

        let lines = CoverageLineIterator.lines(of: segments)

        #expect(lines.map(\.line) == [Int.max - 10])
    }
}

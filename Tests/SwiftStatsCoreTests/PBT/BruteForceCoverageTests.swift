@testable import SwiftStatsCore
import Testing

/// The references the coverage properties compare with (design D12: a
/// reference has examples of its own), each expectation worked out by hand
/// from the rules their headers state: llvm's line rule one line at a time
/// over the prefix a walk reads, the count a point gets from segments and
/// from regions, and runs expanded back into lines.
@Suite("Coverage references")
struct BruteForceCoverageTests {
    /// A segment at `line` and `column` with `count`, none when nil,
    /// entering a region when `entry`, a gap when `gap`.
    private static func segment(_ line: Int, _ column: Int, _ count: Int64?, entry: Bool, gap: Bool)
        -> CoverageSegment {
        CoveragePBT.segment(line, column, count, entry: entry, gap: gap)
    }

    /// A line as `line:count`, `*` when partly run.
    private static func shown(_ lines: [CoverageLineIterator.Line]) -> [String] {
        lines.map(CoveragePBT.shown)
    }

    @Test("a counted segment maps the lines it wraps with its count, and an uncounted one maps none")
    func wrappedLines() {
        let segments = [
            Self.segment(2, 5, 3, entry: true, gap: false),
            Self.segment(4, 1, nil, entry: false, gap: false),
            Self.segment(7, 3, 1, entry: true, gap: false),
            Self.segment(8, 2, nil, entry: false, gap: false)
        ]

        #expect(Self.shown(BruteForceCoverage.lineRule(of: segments)) == ["2:3", "3:3", "4:3", "7:1", "8:1"])
    }

    @Test("""
        a skipped start unmaps its line unless a counted segment enters a region on it; a gap entry maps a line \
        without raising its count; region starts raise the wrapped count, and one that didn't run marks it partly run
        """)
    func lineClauses() {
        let segments = [
            Self.segment(1, 1, 2, entry: true, gap: false),
            Self.segment(2, 1, nil, entry: true, gap: false),
            Self.segment(2, 9, 2, entry: false, gap: false),
            Self.segment(3, 1, nil, entry: true, gap: false),
            Self.segment(3, 4, 0, entry: true, gap: true),
            Self.segment(4, 2, 5, entry: true, gap: false),
            Self.segment(4, 6, 0, entry: true, gap: false),
            Self.segment(5, 1, nil, entry: false, gap: false)
        ]

        let lines = BruteForceCoverage.lineRule(of: segments)

        // Line 3's wrapped segment is line 2's last, counted 2.
        #expect(Self.shown(lines) == ["1:2", "3:2", "4:5*", "5:0"])
    }

    @Test("the walk reads up to a segment on an earlier line; columns going back on one line don't end it")
    func walkedPrefix() {
        let segments = [
            Self.segment(5, 4, 1, entry: true, gap: false),
            Self.segment(5, 2, 1, entry: true, gap: false),
            Self.segment(7, 1, nil, entry: false, gap: false),
            Self.segment(6, 1, 9, entry: true, gap: false),
            Self.segment(9, 1, 9, entry: true, gap: false)
        ]

        let walked = BruteForceCoverage.walkedPrefix(of: segments)

        #expect(walked.map(\.line) == [5, 5, 7])
        #expect(Self.shown(BruteForceCoverage.lineRule(of: segments)) == ["5:1", "6:1", "7:1"])
        #expect(BruteForceCoverage.lineRule(of: []).isEmpty)
    }

    @Test("a point takes the last segment's count at or before it, and none before the first or after an end")
    func segmentCounts() {
        let segments = [
            Self.segment(2, 3, 4, entry: true, gap: false),
            Self.segment(2, 7, nil, entry: false, gap: false),
            Self.segment(3, 1, 6, entry: true, gap: false)
        ]

        let counts = [(2, 2), (2, 3), (2, 6), (2, 7), (2, 99), (3, 1), (40, 1)].map { line, column in
            BruteForceCoverage.count(at: SourcePosition(line: line, column: column), segments: segments)
        }

        #expect(counts == [nil, 4, 4, nil, nil, 6, 6])
    }

    @Test("""
        a point takes its innermost region's count, the end column exclusive; an empty region holds nothing, a \
        skipped one gives none, and identical ranges count as the first kind with its largest count
        """)
    func regionCounts() {
        let regions = [
            CoveragePBT.region((1, 1), (5, 1), 2, kind: CoverageRegion.codeKind),
            CoveragePBT.region((2, 3), (2, 6), 7, kind: CoverageRegion.codeKind),
            CoveragePBT.region((2, 3), (2, 6), 9, kind: CoverageRegion.gapKind),
            CoveragePBT.region((2, 3), (2, 6), 8, kind: CoverageRegion.codeKind),
            CoveragePBT.region((3, 2), (3, 2), 5, kind: CoverageRegion.codeKind),
            CoveragePBT.region((4, 1), (4, 3), 0, kind: CoverageRegion.skippedKind)
        ]

        let counts = [(1, 1), (2, 3), (2, 5), (2, 6), (3, 2), (4, 2), (4, 3), (5, 1)].map { line, column in
            BruteForceCoverage.count(at: SourcePosition(line: line, column: column), regions: regions)
        }

        #expect(counts == [2, 8, 8, 2, 2, nil, 2, nil])
    }

    @Test("runs expand to every line from first to last with their count and flag; a backward run holds none")
    func expandedRuns() {
        let runs = [
            CoverageLineRun(start: 3, end: 5, count: 2, partlyRun: false),
            CoverageLineRun(start: 9, end: 8, count: 1, partlyRun: false),
            CoverageLineRun(start: Int.max, end: Int.max, count: 1, partlyRun: true)
        ]

        #expect(Self.shown(ExpandRuns.lines(of: runs)) == ["3:2", "4:2", "5:2", "\(Int.max):1*"])
    }

    @Test("runs could merge only when the second starts on the line after the first ends, with its count and flag")
    func mergeableRuns() {
        let run = CoverageLineRun(start: 3, end: 5, count: 2, partlyRun: false)

        #expect(ExpandRuns.couldMerge(run, CoverageLineRun(start: 6, end: 6, count: 2, partlyRun: false)))
        #expect(ExpandRuns.couldMerge(run, CoverageLineRun(start: 7, end: 7, count: 2, partlyRun: false)) == false)
        #expect(ExpandRuns.couldMerge(run, CoverageLineRun(start: 6, end: 6, count: 3, partlyRun: false)) == false)
        #expect(ExpandRuns.couldMerge(run, CoverageLineRun(start: 6, end: 6, count: 2, partlyRun: true)) == false)
        #expect(ExpandRuns.couldMerge(
            CoverageLineRun(start: Int.max, end: Int.max, count: 2, partlyRun: false),
            CoverageLineRun(start: Int.min, end: Int.min, count: 2, partlyRun: false)
        ) == false)
    }
}

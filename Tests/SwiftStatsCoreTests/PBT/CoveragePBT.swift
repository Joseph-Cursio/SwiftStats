import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// Properties of reading llvm-cov's export and applying its rules (M5,
/// design §4.1.3, PRD §7.8): the line rule maps exactly what llvm
/// documents, and over any list returns (P2.1); the segments built from
/// well-nested regions give every point the innermost region's count
/// (P2.2); raising a count, adding a skipped region and an untouched line
/// change the lines only as the rule allows (P2.3); runs expand back to
/// their lines (P2.4); deduplicated regions are their ranges' largest
/// (P2.5); and decoding any document returns or throws `CoverageFailure`,
/// reading counts as documented (P2.6). The references are
/// `BruteForceCoverage` and `ExpandRuns`, written from llvm's and the
/// PRD's text. `CoverageLineRuleTests` and `CoverageExportTests` hold the
/// fixed examples; each property here has its own, calling its shared
/// check, and meta-tests that feed a planted defect's output to that check.
@Suite("Coverage export and line rule: properties", .tags(.pbt))
struct CoveragePBT {
    /// P2.1's base runs, over the engine's 100: one walk of a few dozen
    /// segments and the reference's line-by-line answer cost well under a
    /// millisecond, and a walk that a segment on an earlier line ends, the
    /// rarest antecedent, comes in 114 of the meta-test's 1,000 lists
    /// (design D14: `(1 - 0.114)^200`, about 3 * 10^-11, is the most a run
    /// misses it; 100 runs would miss it about 6 * 10^-6 of the time).
    static let lineRuleRuns = 200
    /// What P2.1's tally counts when a line no segment starts on is mapped
    /// by a counted segment wrapping it.
    static let wrapsOnly = "a line only a counted wrap maps"
    /// What it counts when a line's first segment starts a skipped region.
    static let skippedStart = "a line a skipped region starts"
    /// What it counts when a mapped line is partly run.
    static let partlyRun = "a partly run line"
    /// What it counts when a segment on an earlier line ends the walk.
    static let wentBack = "a walk a segment on an earlier line ends"
    /// What it counts when a gap past `CoverageGen.gapCap` lines no count
    /// wraps lies between two segments.
    static let hugeGap = "a gap past the cap no count wraps"
    /// What it counts when a line that ran holds a region start whose count
    /// is below 0.
    static let negativeStart = "a line that ran where a region counted below 0 starts"
    /// The antecedents P2.1 must reach at least once each.
    static let lineRuleAntecedents = [wrapsOnly, skippedStart, partlyRun, wentBack, hugeGap, negativeStart]

    /// The recorded exports: the Coverage, Mutation and Risky fixtures'.
    static let recordedExports = ["Coverage", "Mutation", "Risky"]

    /// The bytes of each recorded export.
    static func recordedData() throws -> [Data] {
        try recordedExports.map { fixture in
            try Data(contentsOf: FakeToolchain.recordedDirectory
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(fixture)
                .appendingPathComponent("Recorded")
                .appendingPathComponent("export.json"))
        }
    }

    /// Records an issue naming `subject`, in ASCII, for each law in `laws`
    /// that fails; whether all hold.
    static func holds(_ laws: [(holds: Bool, law: String)], subject: String) -> Bool {
        for law in laws where law.holds == false {
            Issue.record(Comment(rawValue: PBTTrace.ascii("\(subject) fails: it \(law.law)")))
        }
        return laws.allSatisfy(\.holds)
    }

    /// A segment at `line` and `column` with `count`, or with none when
    /// it is nil, entering a region when `entry`, a gap when `gap`.
    static func segment(_ line: Int, _ column: Int, _ count: Int64?, entry: Bool, gap: Bool) -> CoverageSegment {
        CoverageSegment(
            line: line,
            column: column,
            executionCount: count ?? 0,
            hasCount: count != nil,
            isRegionEntry: entry,
            isGapRegion: gap
        )
    }

    /// `line` as `line:count`, `*` marking a partly run one.
    static func shown(_ line: CoverageLineIterator.Line) -> String {
        "\(line.line):\(line.executionCount)" + (line.partlyRun ? "*" : "")
    }

    /// Where `lines` first differs from `expected`, as text.
    static func difference(_ lines: [CoverageLineIterator.Line], _ expected: [CoverageLineIterator.Line]) -> String {
        let shared = min(lines.count, expected.count)
        let index = (0..<shared).first { lines[$0] != expected[$0] } ?? shared
        let found = index < lines.count ? shown(lines[index]) : "no more lines"
        let wanted = index < expected.count ? shown(expected[index]) : "no more lines"
        return "gives \(lines.count) lines, expected \(expected.count); "
            + "line \(index + 1) is \(found), expected \(wanted)"
    }

    /// The classes `segments` falls in, for P2.1's tally and the
    /// generator's meta-test.
    static func lineRuleLabels(of segments: [CoverageSegment]) -> [String] {
        let walked = BruteForceCoverage.walkedPrefix(of: segments)
        let lines = BruteForceCoverage.lineRule(of: segments)
        let segmentLines = Set(walked.map(\.line))
        let byLine = Dictionary(grouping: walked, by: \.line)
        let startsSkipped = byLine.values.contains { onLine in
            onLine.first.map { $0.isRegionEntry && $0.hasCount == false } ?? false
        }
        let gaps = zip(walked, walked.dropFirst()).contains { pair in
            pair.0.hasCount == false && pair.1.line - pair.0.line > CoverageGen.gapCap
        }
        let negative = lines.contains { line in
            line.ran && (byLine[line.line] ?? []).contains { $0.startsRegion && $0.executionCount < 0 }
        }
        return [
            (lines.contains { segmentLines.contains($0.line) == false }, wrapsOnly),
            (startsSkipped, skippedStart),
            (lines.contains(where: \.partlyRun), partlyRun),
            (walked.count < segments.count, wentBack),
            (gaps, hugeGap),
            (negative, negativeStart)
        ]
        .filter(\.0)
        .map(\.1)
    }

    /// Whether `lines`, what the walk mapped of `segments`, are the lines
    /// llvm's documented rule maps over the prefix the walk reads
    /// (`BruteForceCoverage`). Records an issue when they aren't.
    static func checkLines(_ segments: [CoverageSegment], lines: [CoverageLineIterator.Line]) -> Bool {
        let expected = BruteForceCoverage.lineRule(of: segments)
        return holds(
            [(lines == expected, difference(lines, expected))],
            subject: "the walk over \(segments.count) segments"
        )
    }

    // MARK: P2.1

    /// Invariant: the walk returns for any segment list, and maps exactly
    /// the lines llvm's line rule maps over the prefix whose lines never
    /// go back, with their counts and partly-run flags.
    /// Why it holds: `CoverageLineIterator`'s header and `lines(of:)`'s
    /// doc comment (llvm's `LineCoverageStats` and `LineCoverageIterator`
    /// over the lines from the first segment's to the last's; the walk
    /// stops at a segment on an earlier line, design B3), PRD §7.8 (a
    /// partly run line).
    /// Why it might not: a counted segment maps every line up to the next,
    /// so counted gaps are capped at 1,000 lines (design D7, assumed);
    /// gaps no count wraps go far past that, and unsorted lists come from a
    /// moved segment, since the export's decoder rejects them (U6); counts
    /// below 0, which llvm never writes, are drawn too, since the decoder
    /// reads them as spelled (P2.6).
    /// Oracle: reference (`BruteForceCoverage`, from llvm's documentation);
    /// planted defects: a counted entry no longer mapping its line, the
    /// wrapped segment forgotten after a line with no segment, a skipped
    /// start ignored, counts summed, every counted entry flagging partly
    /// run, a region counted below 0 not flagging it, a walk that skips
    /// counted gaps, and one going on past a segment going back, each
    /// detected.
    /// Tier: Strict (stop-ship).
    @Test(
        "the walk returns for any segments and maps exactly what llvm's line rule maps over those it reads",
        .timeLimit(PBTBudget.timeLimit)
    )
    func linesFollowTheRule() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.lineRuleRuns), input: CoverageGen.segments) { input in
            PBTTrace.note(input)
            Self.lineRuleLabels(of: input.segments).forEach(tally.fire)
            if Self.checkLines(input.segments, lines: CoverageLineIterator.lines(of: input.segments)) == false {
                PBTTrace.firstFailure(input, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.lineRuleAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("every recorded file's segments map the lines llvm's rule maps")
    func recordedFilesFollowTheRule() throws {
        let exports = try Self.recordedData().map(CoverageExport.decode)
        let files = exports.flatMap(\.files)

        #expect(files.count == 37)
        for file in files {
            #expect(Self.checkLines(file.segments, lines: CoverageLineIterator.lines(of: file.segments)))
        }
    }

    @Test("""
        a gap of 4 * 10^7 lines no count wraps maps none of its lines, and a counted segment, an uncounted entry \
        and a skipped start on one line map as llvm's rule says
        """)
    func gapsAndSkippedStarts() {
        let resumed = 4 + 40_000_000
        let segments = [
            Self.segment(1, 1, 2, entry: true, gap: false),
            Self.segment(3, 2, nil, entry: false, gap: false),
            Self.segment(resumed, 1, nil, entry: true, gap: false),
            Self.segment(resumed, 5, 0, entry: true, gap: true),
            Self.segment(resumed + 1, 1, 4, entry: true, gap: false),
            Self.segment(resumed + 1, 9, 0, entry: true, gap: false)
        ]

        let lines = CoverageLineIterator.lines(of: segments)

        #expect(Self.checkLines(segments, lines: lines))
        #expect(lines.map(Self.shown) == ["1:2", "2:2", "3:2", "\(resumed):0", "\(resumed + 1):4*"])
    }

    @Test("""
        a line that ran holding a region entry whose count is below 0 is partly run, since a line runs only \
        when its count is above 0
        """)
    func negativeRegionEntry() {
        let segments = [
            Self.segment(1, 1, 5, entry: true, gap: false),
            Self.segment(1, 5, -1, entry: true, gap: false),
            Self.segment(2, 1, nil, entry: false, gap: false)
        ]

        let lines = CoverageLineIterator.lines(of: segments)

        #expect(Self.checkLines(segments, lines: lines))
        #expect(lines.map(Self.shown) == ["1:5*", "2:-1"])
    }

    @Test("a planted defect's lines fail P2.1's law")
    func lineRuleDefectsDetected() {
        let segments = [
            Self.segment(1, 1, 2, entry: true, gap: false),
            Self.segment(2, 1, nil, entry: true, gap: false),
            Self.segment(2, 9, 2, entry: false, gap: false),
            Self.segment(4, 2, 3, entry: true, gap: false),
            Self.segment(4, 6, 0, entry: true, gap: false),
            Self.segment(5, 1, nil, entry: false, gap: false),
            Self.segment(3, 1, 9, entry: true, gap: false)
        ]
        let lines = CoverageLineIterator.lines(of: segments)
        var skippedStartMapped = lines
        skippedStartMapped.insert(CoverageLineIterator.Line(line: 2, executionCount: 2, partlyRun: false), at: 1)
        var summed = lines
        summed[2] = CoverageLineIterator.Line(line: 4, executionCount: 5, partlyRun: true)
        let wrappedDropped = lines.filter { $0.line != 3 }
        var entriesPartlyRun = lines
        entriesPartlyRun[0] = CoverageLineIterator.Line(line: 1, executionCount: 2, partlyRun: true)
        let pastTheBack = lines + [CoverageLineIterator.Line(line: 6, executionCount: 0, partlyRun: false)]
        let negativeSegments = [
            Self.segment(1, 1, 5, entry: true, gap: false),
            Self.segment(1, 5, -1, entry: true, gap: false)
        ]
        let zeroOnly = [CoverageLineIterator.Line(line: 1, executionCount: 5, partlyRun: false)]

        // Line 2 starts a skipped region; line 3 only line 2's last segment
        // wraps; line 4's count is the largest of 2, 3 and 0; the walk ends
        // at the segment on line 3.
        #expect(lines.map(Self.shown) == ["1:2", "3:2", "4:3*", "5:0"])
        #expect(Self.checkLines(segments, lines: lines))
        PlantedDefect.expectDetected("a skipped start ignored", sourceLocation: #_sourceLocation) {
            Self.checkLines(segments, lines: skippedStartMapped)
        }
        PlantedDefect.expectDetected("counts summed", sourceLocation: #_sourceLocation) {
            Self.checkLines(segments, lines: summed)
        }
        PlantedDefect.expectDetected("a walk that skips counted gaps", sourceLocation: #_sourceLocation) {
            Self.checkLines(segments, lines: wrappedDropped)
        }
        PlantedDefect.expectDetected("every counted entry flagging partly run", sourceLocation: #_sourceLocation) {
            Self.checkLines(segments, lines: entriesPartlyRun)
        }
        PlantedDefect.expectDetected("a walk going on past a segment going back", sourceLocation: #_sourceLocation) {
            Self.checkLines(segments, lines: pastTheBack)
        }
        PlantedDefect.expectDetected("partly run only beside a count of 0", sourceLocation: #_sourceLocation) {
            Self.checkLines(negativeSegments, lines: zeroOnly)
        }
    }
}

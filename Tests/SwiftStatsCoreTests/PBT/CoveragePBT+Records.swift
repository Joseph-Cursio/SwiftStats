//
//  CoveragePBT+Records.swift
//  SwiftStatsCoreTests
//
//  P2.4 and P2.5: a file's mapped lines in runs expand back to those lines,
//  and no two adjacent runs could be one; a record's regions deduplicated
//  are exactly the ranges given, strictly sorted, each with the largest
//  count given for its range.
//

import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P2.4 and P2.5.
extension CoveragePBT {
    /// P2.4's base runs: the engine's default; the rarest antecedent,
    /// adjacent lines split by partly running, comes in 266 of the
    /// meta-test's 1,000 lists (design D14: `(1 - 0.266)^100`, about
    /// 4 * 10^-14).
    static let runsRuns = 100
    /// What P2.4's tally counts when two lines share a run.
    static let sharedRun = "two lines sharing a run"
    /// What it counts when adjacent lines differ only in their count.
    static let countSplits = "adjacent lines split by their count"
    /// What it counts when adjacent lines differ only in partly running.
    static let partlyRunSplits = "adjacent lines split by partly running"
    /// What it counts when lines with one count are split by a gap.
    static let gapSplits = "lines of one count split by a gap"
    /// The antecedents P2.4 must reach at least once each.
    static let runsAntecedents = [sharedRun, countSplits, partlyRunSplits, gapSplits]
    /// P2.5's base runs: the engine's default; both antecedents come in
    /// about 700 of the meta-test's 1,000 lists (design D14).
    static let deduplicatedRuns = 100
    /// What P2.5's tally counts when one range is given twice with
    /// different counts.
    static let differingTwins = "a range given twice with different counts"
    /// What it counts when one range is given with different kinds.
    static let kindTwins = "a range given with different kinds"
    /// The antecedents P2.5 must reach at least once each.
    static let deduplicatedAntecedents = [differingTwins, kindTwins]

    /// The classes `lines` fall in, for P2.4's tally and the generator's
    /// meta-test.
    static func runsLabels(of lines: [CoverageLineIterator.Line]) -> [String] {
        let pairs = Array(zip(lines, lines.dropFirst()))
        let adjacent = pairs.filter { $0.0.line + 1 == $0.1.line }
        let sameCount = { (pair: (CoverageLineIterator.Line, CoverageLineIterator.Line)) in
            pair.0.executionCount == pair.1.executionCount
        }
        let sameFlag = { (pair: (CoverageLineIterator.Line, CoverageLineIterator.Line)) in
            pair.0.partlyRun == pair.1.partlyRun
        }
        return [
            (adjacent.contains { sameCount($0) && sameFlag($0) }, sharedRun),
            (adjacent.contains { sameCount($0) == false && sameFlag($0) }, countSplits),
            (adjacent.contains { sameCount($0) && sameFlag($0) == false }, partlyRunSplits),
            (pairs.contains { $0.0.line + 1 < $0.1.line && sameCount($0) }, gapSplits)
        ]
        .filter(\.0)
        .map(\.1)
    }

    /// Whether `runs`, what `CoverageFileRuns` made of `lines`, expand back
    /// to `lines` (`ExpandRuns`) with no two adjacent runs that could be
    /// one. Records an issue for each law that fails.
    static func checkRuns(_ lines: [CoverageLineIterator.Line], runs: [CoverageLineRun]) -> Bool {
        let expanded = ExpandRuns.lines(of: runs)
        let mergeable = zip(runs, runs.dropFirst()).first { ExpandRuns.couldMerge($0.0, $0.1) }
        return holds(
            [
                (expanded == lines, "expands to lines that " + difference(expanded, lines)),
                (mergeable == nil, mergeable.map { "keeps runs from \($0.0.start) and \($0.1.start) apart" } ?? "")
            ],
            subject: "the runs of \(lines.count) lines"
        )
    }

    /// The classes `regions` fall in, for P2.5's tally and the generator's
    /// meta-test.
    static func deduplicatedLabels(of regions: [CoverageRegion]) -> [String] {
        let byRange = Dictionary(grouping: regions) { SourceSpan(start: $0.start, end: $0.end) }
        return [
            (byRange.values.contains { Set($0.map(\.executionCount)).count > 1 }, differingTwins),
            (byRange.values.contains { Set($0.map(\.kind)).count > 1 }, kindTwins)
        ]
        .filter(\.0)
        .map(\.1)
    }

    /// Whether `deduplicated`, what `CoverageRecordLines.deduplicated` made
    /// of `regions`, holds exactly their ranges, strictly sorted by start,
    /// then end, each with the largest count given for its range; compared
    /// on range and count only. Records an issue for each law that fails.
    static func checkDeduplicated(_ regions: [CoverageRegion], deduplicated: [CoverageRegion]) -> Bool {
        let ranges = regions.map { SourceSpan(start: $0.start, end: $0.end) }
        let kept = deduplicated.map { SourceSpan(start: $0.start, end: $0.end) }
        let largest = Dictionary(zip(ranges, regions.map(\.executionCount)), uniquingKeysWith: max)
        let unsorted = zip(deduplicated, deduplicated.dropFirst()).first { pair in
            (pair.0.start, pair.0.end) >= (pair.1.start, pair.1.end)
        }
        let wrong = deduplicated.first { largest[SourceSpan(start: $0.start, end: $0.end)] != $0.executionCount }
        return holds(
            [
                (Set(kept) == Set(ranges), "keeps \(Set(kept).count) ranges of the \(Set(ranges).count) given"),
                (
                    unsorted == nil,
                    unsorted.map { "puts \(RegionListDraft.shown($0.1)) after \(RegionListDraft.shown($0.0))" } ?? ""
                ),
                (wrong == nil, wrong.map { "keeps \(RegionListDraft.shown($0)), not its range's largest count" } ?? "")
            ],
            subject: "deduplicating \(regions.count) regions"
        )
    }

    // MARK: P2.4

    /// Invariant: expanding the runs `runs(of:)` makes of mapped lines
    /// gives back those lines, and no two adjacent runs could merge.
    /// Why it holds: `CoverageFileRuns`'s header ("consecutive lines with
    /// one count and the same partly-run flag share a run") and
    /// `CoverageLineRun`'s doc comments (first to last line, inclusive).
    /// Why it might not: the lines increase, as the line rule gives them;
    /// a partly run line is one that ran (PRD §7.8).
    /// Oracle: round trip (`ExpandRuns`); planted defects: a gap merged
    /// into a run, partly running ignored, a run's last line dropped, and
    /// runs never merged, each detected.
    /// Tier: Strict (stop-ship).
    @Test(
        "expanding the runs of mapped lines gives them back, and no two adjacent runs could be one",
        .timeLimit(PBTBudget.timeLimit)
    )
    func runsExpandToLines() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.runsRuns), input: CoverageGen.lines) { input in
            PBTTrace.note(input)
            let lines = input.built
            Self.runsLabels(of: lines).forEach(tally.fire)
            if Self.checkRuns(lines, runs: CoverageFileRuns.runs(of: lines)) == false {
                PBTTrace.firstFailure(input, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.runsAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("each recorded file's mapped lines, in runs, expand back to those lines")
    func recordedRunsExpand() throws {
        let files = try Self.recordedData().map(CoverageExport.decode).flatMap(\.files)

        for file in files {
            let lines = CoverageLineIterator.lines(of: file.segments)

            #expect(Self.checkRuns(lines, runs: CoverageFileRuns.runs(of: lines)))
        }
    }

    @Test("lines ending on Int.max make one run, and a partly run line splits a run of one count")
    func edgeRuns() {
        let lines = [
            CoverageLineIterator.Line(line: Int.max - 2, executionCount: 3, partlyRun: false),
            CoverageLineIterator.Line(line: Int.max - 1, executionCount: 3, partlyRun: true),
            CoverageLineIterator.Line(line: Int.max, executionCount: 3, partlyRun: true)
        ]

        let runs = CoverageFileRuns.runs(of: lines)

        #expect(Self.checkRuns(lines, runs: runs))
        #expect(runs == [
            CoverageLineRun(start: Int.max - 2, end: Int.max - 2, count: 3, partlyRun: false),
            CoverageLineRun(start: Int.max - 1, end: Int.max, count: 3, partlyRun: true)
        ])
    }

    // MARK: P2.5

    /// Invariant: `deduplicated`'s ranges are exactly the ranges given,
    /// strictly sorted by start, then end, each with the largest count
    /// given for its range.
    /// Why it holds: `CoverageRecordLines.deduplicated`'s doc comment
    /// ("those of one range merged into one with the largest count, by
    /// start, then end") and PRD §7.8 (a record's regions "deduplicated by
    /// range with the largest count").
    /// Why it might not: compared on range and count only: which region of
    /// equal count is kept, across kinds, is the first given, and isn't
    /// stated (design §4.1.3).
    /// Oracle: postconditions (the code is the dictionary fold a reference
    /// would repeat, design D12); planted defects: the first count kept,
    /// counts summed, and an unstable or non-strict order, each detected.
    /// Tier: Strict (stop-ship).
    @Test(
        "deduplicated regions are exactly the ranges given, strictly sorted, each with its range's largest count",
        .timeLimit(PBTBudget.timeLimit)
    )
    func deduplicatedKeepsLargest() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.deduplicatedRuns), input: CoverageRegionGen.pooled) { input in
            PBTTrace.note(input)
            Self.deduplicatedLabels(of: input.regions).forEach(tally.fire)
            let deduplicated = CoverageRecordLines.deduplicated(input.regions)
            if Self.checkDeduplicated(input.regions, deduplicated: deduplicated) == false {
                PBTTrace.firstFailure(input, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.deduplicatedAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("each recorded entry's code regions deduplicate to their ranges' largest counts")
    func recordedRegionsDeduplicate() throws {
        let entries = try Self.recordedData().map(CoverageExport.decode).flatMap(\.functions)

        for entry in entries {
            let code = entry.regions.filter(\.isCode)

            #expect(Self.checkDeduplicated(code, deduplicated: CoverageRecordLines.deduplicated(code)))
        }
    }

    @Test("a range given three times keeps its largest count, saturated included, wherever it comes")
    func repeatedRanges() {
        let regions = [
            Self.region((2, 1), (3, 4), 5, kind: CoverageRegion.codeKind),
            Self.region((1, 1), (4, 1), 0, kind: CoverageRegion.codeKind),
            Self.region((2, 1), (3, 4), Int64.max, kind: CoverageRegion.gapKind),
            Self.region((2, 1), (3, 4), 1, kind: CoverageRegion.codeKind)
        ]

        let deduplicated = CoverageRecordLines.deduplicated(regions)

        #expect(Self.checkDeduplicated(regions, deduplicated: deduplicated))
        #expect(deduplicated.map(\.executionCount) == [0, Int64.max])
    }

    @Test("a planted defect's runs fail P2.4's law, and its regions P2.5's")
    func recordDefectsDetected() {
        let lines = [(1, false), (2, false), (4, false), (5, true), (6, true)].map { line, partly in
            CoverageLineIterator.Line(line: line, executionCount: 2, partlyRun: partly)
        }
        let gapMerged = [
            CoverageLineRun(start: 1, end: 4, count: 2, partlyRun: false),
            CoverageLineRun(start: 5, end: 6, count: 2, partlyRun: true)
        ]
        let flagIgnored = [
            CoverageLineRun(start: 1, end: 2, count: 2, partlyRun: false),
            CoverageLineRun(start: 4, end: 6, count: 2, partlyRun: false)
        ]
        let lastDropped = CoverageFileRuns.runs(of: lines).map { run in
            CoverageLineRun(start: run.start, end: max(run.start, run.end - 1), count: 2, partlyRun: run.partlyRun)
        }
        let unmerged = lines.map { CoverageLineRun(start: $0.line, end: $0.line, count: 2, partlyRun: $0.partlyRun) }
        let regions = [
            Self.region((2, 1), (3, 4), 1, kind: CoverageRegion.codeKind),
            Self.region((1, 1), (4, 1), 0, kind: CoverageRegion.codeKind),
            Self.region((2, 1), (3, 4), 5, kind: CoverageRegion.codeKind)
        ]
        let deduplicated = CoverageRecordLines.deduplicated(regions)
        let firstKept = [deduplicated[0], regions[0]]
        let summed = [deduplicated[0], regions[0].with(executionCount: 6)]

        #expect(Self.checkRuns(lines, runs: CoverageFileRuns.runs(of: lines)))
        #expect(Self.checkDeduplicated(regions, deduplicated: deduplicated))
        PlantedDefect.expectDetected("a gap merged into a run", sourceLocation: #_sourceLocation) {
            Self.checkRuns(lines, runs: gapMerged)
        }
        PlantedDefect.expectDetected("partly running ignored", sourceLocation: #_sourceLocation) {
            Self.checkRuns(lines, runs: flagIgnored)
        }
        PlantedDefect.expectDetected("a run's last line dropped", sourceLocation: #_sourceLocation) {
            Self.checkRuns(lines, runs: lastDropped)
        }
        PlantedDefect.expectDetected("runs never merged", sourceLocation: #_sourceLocation) {
            Self.checkRuns(lines, runs: unmerged)
        }
        PlantedDefect.expectDetected("the first count kept", sourceLocation: #_sourceLocation) {
            Self.checkDeduplicated(regions, deduplicated: firstKept)
        }
        PlantedDefect.expectDetected("counts summed", sourceLocation: #_sourceLocation) {
            Self.checkDeduplicated(regions, deduplicated: summed)
        }
        PlantedDefect.expectDetected("the order reversed", sourceLocation: #_sourceLocation) {
            Self.checkDeduplicated(regions, deduplicated: deduplicated.reversed())
        }
        PlantedDefect.expectDetected("a range kept twice", sourceLocation: #_sourceLocation) {
            Self.checkDeduplicated(regions, deduplicated: deduplicated + [deduplicated[1]])
        }
    }
}

//
//  CoveragePBT+Flags.swift
//  SwiftStatsCoreTests
//
//  P2.2's flag laws, beside its pointwise law (design D12: the counts a
//  point gets don't say which segments enter a region, which are gaps,
//  or which entries carry a count, and the line rule reads all three).
//  From `CoverageSegmentBuilder`'s header and llvm's segment builder: a
//  segment enters a region where each region starts, unless the region
//  starting there is a gap; a counted segment is a gap segment exactly
//  where the innermost region is a gap; and "where it starts, a segment
//  takes the count of the region around it, its own when there is none;
//  when it comes last or is skipped, that segment has no count".
//

@testable import SwiftStatsCore
import Testing

/// P2.2's flag laws.
extension CoveragePBT {
    /// Whether the region entries of `segments`, what the builder built
    /// from `regions`, sit exactly at the distinct region starts whose
    /// innermost starting region isn't a gap, one each; whether each
    /// counted segment is a gap segment exactly when the innermost region
    /// holding its position is a gap (positions no region holds aside);
    /// and whether each entry has a count unless the region starting there
    /// is skipped, or is empty and comes last or lies in a skipped region.
    /// Records an issue for each law that fails.
    static func checkFlags(_ regions: [CoverageRegion], segments: [CoverageSegment]) -> Bool {
        let entries = segments.filter(\.isRegionEntry)
        let expectedEntries = Set(regions.map(\.start)).filter { start in
            BruteForceCoverage.innermostRegion(starting: start, regions: regions)?.kind != CoverageRegion.gapKind
        }
        .sorted()
        let entryPositions = entries.map { position(of: $0) }.sorted()
        let wrongGap = segments.first { segment in
            let holder = BruteForceCoverage.innermostRegion(holding: position(of: segment), regions: regions)
            guard segment.hasCount, let holder else {
                return false
            }
            return segment.isGapRegion != (holder.kind == CoverageRegion.gapKind)
        }
        let lastStart = regions.map(\.start).max()
        let wrongCount = entries.first { segment in
            entryHasCount(at: position(of: segment), regions: regions, lastStart: lastStart) != segment.hasCount
        }
        let shownEntries = "enters regions at \(entryPositions.map { shown($0) }), where they start at "
            + "\(expectedEntries.map { shown($0) })"
        let shownGap = wrongGap.map { "flags \(GeneratedSegments.shown($0)) against its innermost region" } ?? ""
        let shownCount = wrongCount.map { "gives \(GeneratedSegments.shown($0)) the wrong count flag" } ?? ""
        return holds(
            [
                (entryPositions == expectedEntries, shownEntries),
                (wrongGap == nil, shownGap),
                (wrongCount == nil, shownCount)
            ],
            subject: "the segment flags of \(regions.count) regions"
        )
    }

    /// Whether the entry segment at `start` has a count by the header's
    /// rule, where `lastStart` is the largest start of `regions`; false
    /// when no region starts there (an entry the first law refuses).
    static func entryHasCount(
        at start: SourcePosition,
        regions: [CoverageRegion],
        lastStart: SourcePosition?
    ) -> Bool {
        guard let starting = BruteForceCoverage.innermostRegion(starting: start, regions: regions) else {
            return false
        }
        guard starting.start == starting.end else {
            return starting.isSkipped == false
        }
        if starting.isSkipped || starting.start == lastStart {
            return false
        }
        let around = BruteForceCoverage.innermostRegion(holding: start, regions: regions)
        return around?.isSkipped != true
    }

    /// `position` as `line:column`.
    static func shown(_ position: SourcePosition) -> String {
        "\(position.line):\(position.column)"
    }

    /// `segment` with its entry and gap flags set to `entry` and `gap`.
    private static func flagged(_ segment: CoverageSegment, entry: Bool, gap: Bool) -> CoverageSegment {
        CoverageSegment(
            line: segment.line,
            column: segment.column,
            executionCount: segment.executionCount,
            hasCount: segment.hasCount,
            isRegionEntry: entry,
            isGapRegion: gap
        )
    }

    @Test("a planted defect's segment flags fail P2.2's flag laws")
    func flagDefectsDetected() {
        let regions = [
            Self.region((1, 1), (4, 1), 4, kind: CoverageRegion.codeKind),
            Self.region((1, 5), (2, 3), 0, kind: CoverageRegion.codeKind),
            Self.region((2, 4), (2, 9), 7, kind: CoverageRegion.gapKind),
            Self.region((3, 2), (3, 2), 1, kind: CoverageRegion.codeKind)
        ]
        let segments = CoverageSegmentBuilder.segments(of: regions)
        let allGaps = segments.map { Self.flagged($0, entry: $0.isRegionEntry, gap: $0.hasCount) }
        let entryCleared = segments.map { segment in
            segment.line == 1 && segment.column == 5 ? Self.flagged(segment, entry: false, gap: false) : segment
        }
        let resumeEntered = segments.map { segment in
            segment.line == 2 && segment.column == 3 ? Self.flagged(segment, entry: true, gap: false) : segment
        }
        let lastCounted = segments.map { segment in
            segment.line == 3 && segment.column == 2 && segment.isRegionEntry
                ? Self.segment(3, 2, 4, entry: true, gap: false)
                : segment
        }

        #expect(Self.checkFlags(regions, segments: segments))
        PlantedDefect.expectDetected("every counted segment flagged as a gap", sourceLocation: #_sourceLocation) {
            Self.checkFlags(regions, segments: allGaps)
        }
        PlantedDefect.expectDetected("an entry flag cleared", sourceLocation: #_sourceLocation) {
            Self.checkFlags(regions, segments: entryCleared)
        }
        PlantedDefect.expectDetected("a resuming segment flagged as an entry", sourceLocation: #_sourceLocation) {
            Self.checkFlags(regions, segments: resumeEntered)
        }
        PlantedDefect.expectDetected("an empty last region's entry given a count", sourceLocation: #_sourceLocation) {
            Self.checkFlags(regions, segments: lastCounted)
        }
    }
}

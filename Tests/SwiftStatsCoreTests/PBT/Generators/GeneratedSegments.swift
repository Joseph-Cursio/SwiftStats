//
//  GeneratedSegments.swift
//  SwiftStatsCoreTests
//
//  P2.1's input: a segment list drawn as decisions (`SegmentListDraft`),
//  or the segments `CoverageSegmentBuilder` builds from generated regions
//  (`RegionListDraft`), as a record's are; built once, when drawn. A
//  failure report lists the segments, each `line:column`, its count or `-`
//  for none, and whether it enters a region or a gap, and where they came
//  from.
//

@testable import SwiftStatsCore
import Testing

/// A segment list.
struct GeneratedSegments: Sendable, CustomTestStringConvertible {
    /// Where a list came from.
    enum Source: Sendable {
        /// Built from these regions.
        case built(RegionListDraft)
        /// Drawn as these decisions.
        case drafted(SegmentListDraft)
    }

    /// Where it came from.
    let source: Source
    /// The segments.
    let segments: [CoverageSegment]

    /// The segments, then their source.
    var testDescription: String {
        let origin: String
        switch source {
        case .built(let draft):
            origin = "built from " + draft.testDescription

        case .drafted(let draft):
            origin = draft.move.map { "drafted, segment \($0.source) moved to \($0.target)" } ?? "drafted, sorted"
        }
        return "\(segments.count) segments: " + segments.map(Self.shown).joined(separator: ", ") + "; " + origin
    }

    /// The segments `source` gives.
    init(source: Source) {
        self.source = source
        switch source {
        case .built(let draft):
            segments = CoverageSegmentBuilder.segments(of: draft.regions)

        case .drafted(let draft):
            segments = draft.built
        }
    }

    /// `segment` as `line:column count`, `-` for no count, then `entry`
    /// and `gap` where they hold.
    static func shown(_ segment: CoverageSegment) -> String {
        "\(segment.line):\(segment.column) " + (segment.hasCount ? "\(segment.executionCount)" : "-")
            + (segment.isRegionEntry ? " entry" : "") + (segment.isGapRegion ? " gap" : "")
    }
}

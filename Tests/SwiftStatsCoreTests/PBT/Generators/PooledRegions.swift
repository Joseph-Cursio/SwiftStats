//
//  PooledRegions.swift
//  SwiftStatsCoreTests
//
//  P2.5's input: regions whose ends come from a few lines and columns, so
//  ranges repeat, with any kind and count. They need not nest, and an end
//  may come before its start: `CoverageRecordLines.deduplicated` merges by
//  range whatever the ranges are. A failure report lists them.
//

@testable import SwiftStatsCore
import Testing

/// Regions whose ranges repeat.
struct PooledRegions: Sendable, CustomTestStringConvertible {
    /// The regions, in order.
    let regions: [CoverageRegion]

    /// Each region, `start-end kind count`.
    var testDescription: String {
        "\(regions.count) regions: " + regions.map(RegionListDraft.shown).joined(separator: ", ")
    }
}

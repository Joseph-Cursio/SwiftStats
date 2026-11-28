//
//  RegionChange.swift
//  SwiftStatsCoreTests
//
//  P2.3's input: well-nested regions (`RegionListDraft`) with empty ones
//  left out, the index of the region whose count is raised, by a small or
//  large step or to saturation, and the index of the skipped region left
//  out, each taken modulo how many regions it can apply to. Raising
//  changes no range and leaving out a region keeps the rest well nested,
//  with one kind per identical range. Empty regions are left out because
//  llvm's builder makes an empty region that comes last a skipped start
//  (an entry with no count), and one before another region an entry with
//  the enclosing count, so a region added after it can map its line
//  (`CoveragePBT.emptyRegionComingLast` pins that); P2.2 covers empty
//  regions. A failure report shows the regions and both changes.
//

@testable import SwiftStatsCore
import Testing

/// Well-nested regions, one count raised and one skipped region left out.
struct RegionChange: Sendable, CustomTestStringConvertible {
    /// The regions.
    let draft: RegionListDraft
    /// The index of the region raised, modulo the regions' count.
    let raisedIndex: Int
    /// What the raise adds; nil when it saturates.
    let raise: Int64?
    /// The index of the skipped region left out, modulo the skipped
    /// regions' count.
    let removedIndex: Int

    /// The regions, empty ones left out.
    var regions: [CoverageRegion] {
        draft.regions.filter { $0.start != $0.end }
    }

    /// The index of the region raised; nil when there is none.
    var raised: Int? {
        regions.isEmpty ? nil : raisedIndex % regions.count
    }

    /// The regions with one count raised: by `raise`, saturating, or to
    /// `Int64.max`.
    var raisedRegions: [CoverageRegion] {
        var regions = regions
        guard let raised else {
            return regions
        }
        let count = regions[raised].executionCount
        let sum = raise.map { count.addingReportingOverflow($0) }
        let higher = sum.map { $0.overflow ? Int64.max : $0.partialValue } ?? Int64.max
        regions[raised] = regions[raised].with(executionCount: higher)
        return regions
    }

    /// The index of the skipped region left out; nil when there is none.
    var removed: Int? {
        let skipped = regions.indices.filter { regions[$0].isSkipped }
        return skipped.isEmpty ? nil : skipped[removedIndex % skipped.count]
    }

    /// The regions without the skipped region left out.
    var withoutSkipped: [CoverageRegion] {
        var regions = regions
        if let removed {
            regions.remove(at: removed)
        }
        return regions
    }

    /// The regions, then which is raised and which skipped region is left
    /// out.
    var testDescription: String {
        let raising = raised.map { "raising region \($0 + 1) " + (raise.map { "by \($0)" } ?? "to saturation") }
        let leaving = removed.map { "leaving out region \($0 + 1)" }
        let shown = regions.map(RegionListDraft.shown).joined(separator: ", ")
        return "\(regions.count) regions: " + shown + "; "
            + [raising ?? "nothing raised", leaving ?? "no skipped region"].joined(separator: ", ")
    }
}

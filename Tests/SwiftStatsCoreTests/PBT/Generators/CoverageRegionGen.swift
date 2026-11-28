//
//  CoverageRegionGen.swift
//  SwiftStatsCoreTests
//
//  Coverage regions for P2.2, P2.3 and P2.5. Well-nested regions are drawn
//  as decisions (`RegionListDraft`): regions open and close as a cursor
//  moves, so they nest, share a start or an end with the region around
//  them, repeat its range, sit side by side, or are empty; every kind
//  comes up (code most, then skipped and gap, then expansion), with counts
//  of 0, small, large, and saturated. Advances of a column or two, of a
//  line or so, and of up to `regionGap` lines (assumed: enough for lines
//  no region touches; design D7 caps gaps at 1,000 lines, and the grid
//  P2.2 scans grows with every line). P2.3's change raises one region's
//  count and leaves out one skipped region (`RegionChange`). P2.5's
//  regions need not nest: their ends come from a few lines and columns,
//  so ranges repeat, with any kind and count.
//

import PropertyBased
@testable import SwiftStatsCore

/// Generators of coverage regions.
enum CoverageRegionGen {
    /// Columns to a line in a drafted region list (assumed: enough for a
    /// line to hold a start, an inner region and an end).
    static let width = 4
    /// The longest advance, in lines (assumed, as the header says).
    static let regionGap = 12
    /// How many decisions a region list has (design D7).
    static let stepCount = 0...30
    /// How many regions P2.5's list has (design D7).
    static let regionCount = 0...30
    /// A short advance, in columns.
    static let shortAdvance = 1...2
    /// The longest advance of about a line, in lines (assumed).
    static let lineSpan = 2
    /// An advance of about a line, in columns.
    static let lineAdvance = width...(width * lineSpan)
    /// A long advance, in columns.
    static let longAdvance = (width * lineSpan + 1)...(width * regionGap)
    /// The largest small count (assumed: enough to differ, and to tie).
    static let smallCount: Int64 = 3
    /// A large count.
    static let largeCount: Int64 = 1_000
    /// The largest index a change draws, taken modulo how many regions it
    /// can apply to.
    static let largestIndex = 99
    /// What a raise adds, when it doesn't saturate.
    static let raises: [Int64] = [1, largeCount]
    /// The lines P2.5's ends lie on (assumed: few, so ranges repeat).
    static let endLines = 1...2
    /// The columns they lie at (assumed, as above).
    static let endColumns = 1...3
    /// All kinds.
    static let kinds = CoverageRegion.codeKind...CoverageRegion.gapKind

    /// Weight of opening a region.
    static let openWeight = 4.0
    /// Weight of closing one.
    static let closeWeight = 3.0
    /// Weight of moving the cursor.
    static let advanceWeight = 5.0
    /// Weight of a short advance.
    static let shortWeight = 4.0
    /// Weight of a code region.
    static let codeWeight = 4.0
    /// Weight of a skipped or gap region.
    static let otherKindWeight = 2.0
    /// Weight of each other class.
    static let classWeight = 1.0
    /// Weight of a small count.
    static let smallWeight = 3.0
    /// Weight of a count of 0.
    static let zeroWeight = 2.0
    /// The share of region lists given to the builder reversed.
    static let reversedRate: Float = 0.5
    /// The share of raises that saturate.
    static let saturatingRate: Float = 0.25

    /// A region's kind.
    static let kind = Gen.frequency(
        (codeWeight, Gen.always(CoverageRegion.codeKind)),
        (classWeight, Gen.always(CoverageRegion.expansionKind)),
        (otherKindWeight, Gen.always(CoverageRegion.skippedKind)),
        (otherKindWeight, Gen.always(CoverageRegion.gapKind))
    )

    /// A region's count: 0, small, large, or saturated.
    static let count = Gen.frequency(
        (zeroWeight, Gen.always(Int64.zero)),
        (smallWeight, Gen<Int64>.value(in: 1...smallCount)),
        (classWeight, Gen.always(largeCount)),
        (classWeight, Gen.always(Int64.max))
    )

    /// How far the cursor moves.
    static let advance = Gen.frequency(
        (shortWeight, Gen<Int>.value(in: shortAdvance)),
        (otherKindWeight, Gen<Int>.value(in: lineAdvance)),
        (classWeight, Gen<Int>.value(in: longAdvance))
    )

    /// One decision.
    static let step = Gen.frequency(
        (openWeight, zip(kind, count).map(RegionListDraft.Step.open)),
        (closeWeight, Gen.always(RegionListDraft.Step.close)),
        (advanceWeight, advance.map(RegionListDraft.Step.advance))
    )

    /// Well-nested regions, P2.2's input.
    static let regions = zip(step.array(of: stepCount), Gen.bool(reversedRate))
        .map(RegionListDraft.init)
        .eraseToAny()

    /// P2.3's input: well-nested regions, one region's count raised, and
    /// one skipped region left out.
    static let change = zip(
        regions,
        Gen<Int>.value(in: 0...largestIndex),
        Pick.element(of: raises).optional(valueRate: 1 - saturatingRate),
        Gen<Int>.value(in: 0...largestIndex)
    )
    .map(RegionChange.init)
    .eraseToAny()

    /// A position P2.5's ends lie at.
    static let end = zip(Gen<Int>.value(in: endLines), Gen<Int>.value(in: endColumns))
        .map(SourcePosition.init)

    /// One region whose range likely repeats.
    static let pooledRegion = zip(end, end, count, Gen<Int>.value(in: kinds))
        .map { start, end, count, kind in
            CoverageRegion(start: start, end: end, executionCount: count, fileID: 0, expandedFileID: 0, kind: kind)
        }

    /// P2.5's input: regions whose ranges repeat.
    static let pooled = pooledRegion.array(of: regionCount)
        .map(PooledRegions.init)
        .eraseToAny()
}

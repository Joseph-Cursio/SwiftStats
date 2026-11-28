//
//  RegionListDraft.swift
//  SwiftStatsCoreTests
//
//  Well-nested coverage regions as decisions, the input of P2.2 and the
//  base of P2.3's: a cursor moves along the file (`advance`), and a region
//  opens where it is (`open`) and closes where it is later (`close`),
//  innermost first, so every two regions are disjoint or one holds the
//  other; regions still open at the end close there. A region closed where
//  it opened is empty. Positions are offsets, `CoverageRegionGen.width`
//  columns to a line, so a long advance leaves lines no region touches.
//  Regions of one range all take the kind of the first closed (design
//  §4.1.3: one kind per identical range), and a skipped region's count is
//  0, as llvm writes it. An empty region no other region holds is left
//  out: llvm's builder gives it its own count until the next region starts
//  ("otherwise use its predecessor's count", its own when no region is
//  active), so the lines up to that region map though no region holds
//  them; `CoveragePBT.unheldEmptyRegion` pins that. The regions come in
//  closing order, or reversed, since the builder sorts them itself. A
//  failure report lists them.
//

@testable import SwiftStatsCore
import Testing

/// Well-nested coverage regions as decisions.
struct RegionListDraft: Hashable, Sendable, CustomTestStringConvertible {
    /// One decision.
    enum Step: Hashable, Sendable {
        /// The cursor moves on this many columns.
        case advance(Int)
        /// The innermost open region closes at the cursor.
        case close
        /// A region of this kind and count opens at the cursor.
        case open(kind: Int, count: Int64)
    }

    /// A region's range, as offsets.
    private struct Range: Hashable {
        /// Where it starts.
        let start: Int
        /// Where it ends, exclusive.
        let end: Int
    }

    /// A region as offsets, before its kind is settled.
    private struct Drafted {
        /// Its range.
        let range: Range
        /// Its kind.
        let kind: Int
        /// Its count.
        let count: Int64
    }

    /// The names of the region kinds, by kind.
    static let kindNames = ["code", "expansion", "skipped", "gap"]

    /// The decisions, in order.
    let steps: [Step]
    /// Whether the regions come reversed.
    let reversed: Bool

    /// The regions the decisions make.
    var regions: [CoverageRegion] {
        var cursor = 0
        var open: [Drafted] = []
        var closed: [Drafted] = []
        for step in steps {
            switch step {
            case .advance(let columns):
                cursor += columns

            case .close:
                if let region = open.popLast() {
                    closed.append(Self.closing(region, at: cursor))
                }

            case let .open(kind, count):
                open.append(Drafted(range: Range(start: cursor, end: cursor), kind: kind, count: count))
            }
        }
        while let region = open.popLast() {
            closed.append(Self.closing(region, at: cursor))
        }
        var kinds: [Range: Int] = [:]
        let settled = closed.map { region in
            let kind = kinds[region.range] ?? region.kind
            kinds[region.range] = kind
            return CoverageRegion(
                start: Self.position(region.range.start),
                end: Self.position(region.range.end),
                executionCount: kind == CoverageRegion.skippedKind ? 0 : region.count,
                fileID: 0,
                expandedFileID: 0,
                kind: kind
            )
        }
        let held = settled.filter { region in
            region.start != region.end
                || settled.contains { $0.start <= region.start && region.start < $0.end }
        }
        return reversed ? held.reversed() : held
    }

    /// Each region, `start-end kind count`, positions as `line:column`.
    var testDescription: String {
        let shown = regions.map(Self.shown)
        return "\(shown.count) regions\(reversed ? ", reversed" : ""): " + shown.joined(separator: ", ")
    }

    /// The position at `offset`.
    static func position(_ offset: Int) -> SourcePosition {
        SourcePosition(
            line: offset / CoverageRegionGen.width + 1,
            column: offset % CoverageRegionGen.width + 1
        )
    }

    /// `region`, open, closed at `cursor`.
    private static func closing(_ region: Drafted, at cursor: Int) -> Drafted {
        Drafted(range: Range(start: region.range.start, end: cursor), kind: region.kind, count: region.count)
    }

    /// `region` as `start-end kind count`.
    static func shown(_ region: CoverageRegion) -> String {
        let kind = kindNames.indices.contains(region.kind) ? kindNames[region.kind] : "kind \(region.kind)"
        return "\(region.start.line):\(region.start.column)-\(region.end.line):\(region.end.column) "
            + "\(kind) \(region.executionCount)"
    }
}

import PropertyBased
@testable import SwiftStatsCore
import Testing

/// What the coverage generators draw (design D14): from a fixed seed, a
/// thousand draws of each reach each class and each antecedent its
/// property depends on an exact number of times: segment lists (wrapped
/// lines, skipped starts, partly run lines, lines that ran where a region
/// counted below 0 starts, walks a segment going back ends, gaps past the
/// cap, each source and anchor), well-nested regions
/// (empty regions, repeated ranges, points in skipped and gap regions and
/// between regions), their changes (a raise raising a line, a skipped
/// region hiding one, an untouched line), mapped lines (shared runs and
/// each way a run splits), pooled regions (repeated ranges with differing
/// counts and kinds), and export documents (each outcome, each fault, and
/// a file after the first whose segments go back).
/// The counts hold under this engine's generator code and this standard
/// library; a change to either, or to a weight or list in the generators,
/// redraws them.
@Suite("Coverage generators")
struct CoverageGenTests {
    /// The draws each meta-test makes.
    static let draws = 1_000
    /// The attempts allowed per draw: no coverage generator rejects a
    /// value, so one is always enough.
    static let attempts = 1
    /// The fixed seed the meta-tests draw from.
    static let seeded = Xoshiro(seed: (1, 2, 3, 4))

    /// The count of each class over a thousand draws of `generator`, each
    /// draw's classes from `labels`.
    static func counts<Input>(
        _ generator: Generator<Input, AnySequence<Any>>,
        labels: (Input) -> [String]
    ) throws -> [String: Int] {
        var random = seeded
        var counts: [String: Int] = [:]
        for _ in 0..<draws {
            for label in labels(try generator.run(using: &random, limit: attempts)) {
                counts[label, default: 0] += 1
            }
        }
        return counts
    }

    /// The classes of `input`, P2.1's.
    static func segmentLabels(of input: GeneratedSegments) -> [String] {
        var labels = CoveragePBT.lineRuleLabels(of: input.segments)
        switch input.source {
        case .built:
            labels.append("built from regions")

        case .drafted(let draft):
            labels.append(draft.move == nil ? "drafted sorted" : "drafted with a segment moved")
            if case .end = draft.anchor, draft.segments.isEmpty == false {
                labels.append("ending on Int.max")
            }
            if draft.anchor == .start(Int.min), draft.segments.isEmpty == false {
                labels.append("starting at Int.min")
            }
        }
        let positions = input.segments.map(CoveragePBT.position(of:))
        if zip(positions, positions.dropFirst()).contains(where: ==) {
            labels.append("two segments sharing a position")
        }
        return labels
    }

    /// The classes of `draft`, P2.2's.
    static func regionLabels(of draft: RegionListDraft) -> [String] {
        let regions = draft.regions
        return CoveragePBT.pointwiseLabels(of: regions) + [
            (draft.reversed, "reversed"),
            (regions.contains { $0.kind == CoverageRegion.expansionKind }, "an expansion region"),
            (regions.contains { $0.executionCount == Int64.max }, "a saturated count")
        ]
        .filter(\.0)
        .map(\.1)
    }

    /// The classes of `change`, P2.3's.
    static func changeLabels(of change: RegionChange) -> [String] {
        let base = CoverageLineIterator.lines(of: CoverageSegmentBuilder.segments(of: change.regions))
        let raised = CoverageLineIterator.lines(of: CoverageSegmentBuilder.segments(of: change.raisedRegions))
        let without = CoverageLineIterator.lines(of: CoverageSegmentBuilder.segments(of: change.withoutSkipped))
        return CoveragePBT.monotoneLabels(of: change, base: base, raised: raised, withoutSkipped: without) + [
            (change.removed != nil, "a skipped region left out"),
            (change.raised != nil && change.raise == nil, "a raise to saturation")
        ]
        .filter(\.0)
        .map(\.1)
    }

    /// The classes of `draft`, P2.4's.
    static func lineLabels(of draft: MappedLinesDraft) -> [String] {
        let lines = draft.built
        return CoveragePBT.runsLabels(of: lines) + [
            (lines.last?.line == Int.max, "ending on Int.max"),
            (lines.first?.line == Int.min, "starting at Int.min"),
            (lines.contains(where: \.partlyRun), "a partly run line")
        ]
        .filter(\.0)
        .map(\.1)
    }

    /// The classes of `input`, P2.6's.
    static func exportLabels(of input: GeneratedExport) -> [String] {
        let fault = "\(input.draft.fault)"
        let name = fault.prefix { $0 != "(" }
        return CoveragePBT.exportLabels(of: input.draft) + ["fault: \(name)"]
            + (input.draft.expected == .unknown ? ["an outcome left open"] : [])
    }

    @Test("a thousand segment lists reach each antecedent of P2.1, each source and anchor an exact number of times")
    func segmentClasses() throws {
        let counts = try Self.counts(CoverageGen.segments, labels: Self.segmentLabels(of:))

        #expect(counts == [
            "a gap past the cap no count wraps": 157,
            "a line a skipped region starts": 562,
            "a line only a counted wrap maps": 690,
            "a line that ran where a region counted below 0 starts": 126,
            "a partly run line": 371,
            "a walk a segment on an earlier line ends": 114,
            "built from regions": 351,
            "drafted sorted": 496,
            "drafted with a segment moved": 153,
            "ending on Int.max": 103,
            "starting at Int.min": 94,
            "two segments sharing a position": 347
        ])
    }

    @Test("a thousand region lists reach each antecedent of P2.2 an exact number of times")
    func regionClasses() throws {
        let counts = try Self.counts(CoverageRegionGen.regions, labels: Self.regionLabels(of:))

        #expect(counts == [
            "a point between regions": 159,
            "a point in a gap region": 386,
            "a point in a skipped region": 387,
            "a range held twice": 484,
            "a saturated count": 338,
            "an empty region": 430,
            "an expansion region": 259,
            "reversed": 504
        ])
    }

    @Test("a thousand region changes reach each antecedent of P2.3 an exact number of times")
    func changeClasses() throws {
        let counts = try Self.counts(CoverageRegionGen.change, labels: Self.changeLabels(of:))

        #expect(counts == [
            "a line no region touches between regions": 87,
            "a raise to saturation": 214,
            "a raised count raising a line's": 401,
            "a skipped region hiding a line": 128,
            "a skipped region left out": 377
        ])
    }

    @Test("a thousand lists of mapped lines reach each antecedent of P2.4 an exact number of times")
    func lineClasses() throws {
        let counts = try Self.counts(CoverageGen.lines, labels: Self.lineLabels(of:))

        #expect(counts == [
            "a partly run line": 821,
            "adjacent lines split by partly running": 266,
            "adjacent lines split by their count": 854,
            "ending on Int.max": 118,
            "lines of one count split by a gap": 555,
            "starting at Int.min": 148,
            "two lines sharing a run": 719
        ])
    }

    @Test("a thousand pooled region lists reach each antecedent of P2.5 an exact number of times")
    func pooledClasses() throws {
        let counts = try Self.counts(CoverageRegionGen.pooled) { CoveragePBT.deduplicatedLabels(of: $0.regions) }

        #expect(counts == [
            "a range given twice with different counts": 717,
            "a range given with different kinds": 698
        ])
    }

    @Test("a thousand export documents reach each outcome and each fault of P2.6 an exact number of times")
    func exportClasses() throws {
        let counts = try Self.counts(CoverageExportGen.export, labels: Self.exportLabels(of:))

        #expect(counts == [
            "a count past Int64.max read as Int64.max": 269,
            "a document refused with a reason of its own": 207,
            "a document that can't be read": 332,
            "a document that decodes": 347,
            "a file after the first refused for segments going back": 49,
            "a row longer than llvm writes": 179,
            "an outcome left open": 114,
            "fault: badByte": 67,
            "fault: dataCount": 50,
            "fault: misordered": 52,
            "fault: missing": 75,
            "fault: mistyped": 71,
            "fault: outOfRange": 71,
            "fault: shortRow": 71,
            "fault: sound": 363,
            "fault: truncated": 62,
            "fault: wrongType": 47,
            "fault: wrongVersion": 71
        ])
    }
}

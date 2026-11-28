//
//  IntegerEdgesPBT+Clones.swift
//  SwiftStatsCoreTests
//
//  P15.1's clone path: swift-clone-detector's four reports, read as the
//  collector reads them (`SwiftCloneDetectorAdapter.read(_:pass:)`), then
//  merged and attached by `CloneMapper`, every number an integer edge. A
//  copy with a position below 1 or ending before it starts fails the run,
//  naming it; any other copy is attached with its end made inclusive and,
//  on line 1 of a file starting with a byte order mark, its columns
//  shifted past the mark and kept at `Int.max` when the shift would pass
//  it (B25's 04b): held by the record holding it, if any, covering the
//  records it holds whole, and counting the lines holding a token within
//  its lines. Its examples, and a meta-test that feeds a planted defect's
//  mapping (04b undone as a wrapping add) to its check.
//

import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P15.1's clone path.
extension IntegerEdgesPBT {
    /// What reading the four reports and mapping them gave: the mapping,
    /// or the failure reading them gave.
    typealias CloneOutcome = Result<CloneMapping?, any Error>

    /// The clone path's base runs, over the engine's 100: reading four
    /// small reports and mapping two copies costs about a hundred
    /// microseconds. The rarest antecedent, a copy held by a record, came
    /// in 9,086 of 200,000 reports drawn from 200 seeds (4.54%; at least
    /// 4.39% at 99.9% confidence; the meta-test's one seed gives 52 of
    /// 1,000, above the rate), and a column too large to shift in 5.6%.
    /// Design D14: `(1 - 0.0439)^350`, about 1.5 * 10^-7, is the most a run
    /// misses one; 300 runs would miss it about 10^-6 of the time.
    static let cloneRuns = 350
    /// What the clone path's tally counts when a copy has a position below
    /// 1, the first fault of the run.
    static let belowOne = "a copy with a position below 1"
    /// What it counts when a copy ends before it starts, the first fault.
    static let inverted = "a copy ending before it starts"
    /// What it counts when a column on line 1 after a byte order mark is
    /// too large to shift.
    static let saturated = "a column after a byte order mark too large to shift"
    /// The antecedents the clone path must reach at least once each.
    static let cloneAntecedents = [belowOne, inverted, mapped, unknown, saturated, largest]
    /// A copy of the file starting with a byte order mark at 1:`Int.max`,
    /// both of whose columns are too large to shift, held by `marked()`;
    /// and an empty one of the file without at 1:1, held by `first()`.
    static let saturatingClones = CloneEdgeDraft(
        copies: [
            CloneEdgeDraft.Copy(
                marked: true,
                first: CloneEdgeDraft.Position(line: 1, column: Int.max),
                second: CloneEdgeDraft.Position(line: 1, column: Int.max),
                ordered: false
            ),
            CloneEdgeDraft.Copy(
                marked: false,
                first: CloneEdgeDraft.Position(line: 1, column: 1),
                second: CloneEdgeDraft.Position(line: 1, column: 1),
                ordered: false
            )
        ],
        mass: Int.max,
        lineSpan: Int.max - 1,
        duplicatedLines: [0, 1, Int.max - 1, Int.max - IntegerEdgeGen.belowMaximum]
    )

    /// The four runs' reports in `outputs`, as a collector run that ran.
    static func cloneRun(_ outputs: [CloneDetectorPass: CloneDetectorOutput]) -> CloneRun {
        CloneRun(
            status: CollectorStatus(
                name: SwiftCloneDetectorAdapter.name,
                state: .ran,
                version: nil,
                reason: nil,
                options: []
            ),
            executable: nil,
            milliseconds: 0,
            fileListHash: "",
            outputs: outputs
        )
    }

    /// Whether `outcome`, what `draft`'s reports gave mapped onto
    /// `library`, is what the collector's and the mapper's rules give: the
    /// run refused, naming the first copy at fault, exactly when one is;
    /// else one class of the drafted mass and line span, each run's count
    /// kept, and each copy attached at its range, held by the record
    /// holding it, if any, covering the records it holds, its token lines
    /// counted. Records an issue for each law that fails.
    static func checkClones(_ draft: CloneEdgeDraft, outcome: CloneOutcome, library: Library) -> Bool {
        let subject = "mapping the clone reports"
        if let copy = draft.copies.first(where: { malformation(of: $0) != nil }) {
            let fault = malformation(of: copy) ?? ""
            let named = "a copy of \(copy.path) at \(copy.start.line):\(copy.start.column)-"
                + "\(copy.end.line):\(copy.end.column), which \(fault)"
            guard case .failure(let error) = outcome else {
                return holds([(false, "maps a run holding \(named): \(outcome)")], subject: subject)
            }
            let law = (holds: "\(error)".hasSuffix(named), law: "refuses it as \(error), not naming \(named)")
            return holds([law], subject: subject)
        }
        guard case .success(let mapping?) = outcome else {
            return holds([(false, "gives \(outcome), not a mapping")], subject: subject)
        }
        let classes = mapping.report.classes
        let counts = mapping.report.toolDuplicatedLines
        var laws = [
            (classes.count == 1, "gives \(classes.count) classes, not one"),
            (
                classes.first.map { ($0.mass, $0.lineSpan) == (draft.mass, draft.lineSpan) } == true,
                "keeps the mass and line span as \(classes.map { ($0.mass, $0.lineSpan) })"
            ),
            (
                [counts.subtree, counts.nearMiss, counts.sequence, counts.type1] == draft.duplicatedLines,
                "keeps each run's duplicated lines as \(counts)"
            )
        ]
        let instances = classes.first?.instances ?? []
        let expected = draft.copies.map { ($0.path, range(of: $0)) }
        laws.append((
            instances.map(\.file).sorted() == expected.map(\.0).sorted()
                && Set(instances.map(\.range)) == Set(expected.map(\.1)),
            "attaches the copies at \(instances.map { ($0.file, $0.range) }), expected \(expected)"
        ))
        for instance in instances {
            laws += checkInstance(instance, library: library)
        }
        return holds(laws, subject: subject)
    }

    /// Counts in `tally` what `outcome` shows: a copy held by a record, and
    /// one held by none.
    static func tallyClones(_ outcome: CloneOutcome, in tally: AntecedentTally) {
        guard case .success(let mapping?) = outcome else {
            return
        }
        let instances = mapping.report.classes.flatMap(\.instances)
        if instances.contains(where: { $0.containing != nil }) {
            tally.fire(mapped)
        }
        if instances.contains(where: { $0.containing == nil }) {
            tally.fire(unknown)
        }
    }

    // MARK: P15.1, clones

    /// Invariant: swift-clone-detector's reports, every number an integer
    /// edge, are refused naming the first copy with a position below 1 or
    /// ending before it starts; otherwise mapped, each copy at its range,
    /// shifted past a byte order mark on line 1 and kept at `Int.max` when
    /// that would pass it, held by the record holding it or by none, and
    /// nothing traps.
    /// Why it holds: `CloneDetectorOutput.Instance.malformation` and the
    /// adapter's `checkPositions` (PRD §7.12), `CloneMapper`'s header and
    /// `span(of:)` (exclusive ends made inclusive, B25's 04b saturation).
    /// Why it might not: one class of two copies in two small files, none
    /// of whose records is nested, so the record holding a copy is the
    /// innermost; `recordSpans` and `tokenLines` are pinned by
    /// `libraryIsAsStated`, the token lines against both the sources and
    /// the scan's count, apart from the mapper.
    /// Oracle: postconditions from the rules above, worked out apart from
    /// the mapper; planted defects: 04b undone (a trapping add, detected as
    /// a trap), the line-1 test dropped from the shift, the adapter's
    /// position check dropped (detected as a refusal missed, or as the
    /// mapper's inverted-range trap), and (meta-test) 04b undone as a
    /// wrapping add, each detected.
    /// Tier: Strict (stop-ship).
    @Test(
        """
        clone reports at the integer edges are refused for a copy at fault or mapped at their shifted ranges, \
        and nothing traps
        """,
        .timeLimit(PBTBudget.timeLimit)
    )
    func cloneEdgesMap() async throws {
        let library = try Library()
        defer { library.remove() }
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.cloneRuns), input: IntegerEdgeGen.clones) { draft in
            PBTTrace.note(draft)
            Self.cloneLabels(of: draft).filter { $0 != Self.mapped && $0 != Self.unknown }.forEach(tally.fire)
            let outcome = CloneOutcome {
                var outputs: [CloneDetectorPass: CloneDetectorOutput] = [:]
                for pass in CloneDetectorPass.runOrder {
                    outputs[pass] = try SwiftCloneDetectorAdapter.read(draft.report(of: pass), pass: pass)
                }
                return CloneMapper(measured: library.measured).mapping(of: Self.cloneRun(outputs))
            }
            Self.tallyClones(outcome, in: tally)
            if Self.checkClones(draft, outcome: outcome, library: library) == false {
                PBTTrace.firstFailure(draft, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.cloneAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("""
        a copy at 1:Int.max after a byte order mark is kept at Int.max and held by marked(), and one at 1:1 is \
        held by first(), as the 04b example in CloneRunTests
        """)
    func saturatingCloneMaps() throws {
        let library = try Library()
        defer { library.remove() }
        let draft = Self.saturatingClones

        let outcome = CloneOutcome {
            var outputs: [CloneDetectorPass: CloneDetectorOutput] = [:]
            for pass in CloneDetectorPass.runOrder {
                outputs[pass] = try SwiftCloneDetectorAdapter.read(draft.report(of: pass), pass: pass)
            }
            return CloneMapper(measured: library.measured).mapping(of: Self.cloneRun(outputs))
        }

        #expect(Self.checkClones(draft, outcome: outcome, library: library))
        let instances = try outcome.get()?.report.classes.first?.instances ?? []
        #expect(instances.map(\.range) == [Self.span(1, Int.max, 1, Int.max), Self.span(1, 1, 1, 0)])
        #expect(instances.map(\.containing) == ["Lib::func marked() -> Int", "Lib::func first() -> Int"])
    }

    @Test("a copy starting at line 0, or ending before it starts at Int.max, fails the run, naming it")
    func faultyClonesRefused() throws {
        let library = try Library()
        defer { library.remove() }
        let start = CloneEdgeDraft.Position(line: 0, column: 1)
        let end = CloneEdgeDraft.Position(line: 1, column: Int.max)
        let atZero = CloneEdgeDraft(
            copies: [
                CloneEdgeDraft.Copy(marked: false, first: start, second: end, ordered: true),
                CloneEdgeDraft.Copy(marked: true, first: end, second: start, ordered: false)
            ],
            mass: 1,
            lineSpan: 0,
            duplicatedLines: [0, 0, 0, 0]
        )
        let backwards = CloneEdgeDraft(
            copies: [
                CloneEdgeDraft.Copy(marked: false, first: end, second: end, ordered: true),
                CloneEdgeDraft.Copy(marked: true, first: end, second: .init(line: 1, column: 1), ordered: false)
            ],
            mass: Int.max,
            lineSpan: Int.max,
            duplicatedLines: [Int.max, Int.max, Int.max, Int.max]
        )

        for draft in [atZero, backwards] {
            let outcome = CloneOutcome {
                var outputs: [CloneDetectorPass: CloneDetectorOutput] = [:]
                for pass in CloneDetectorPass.runOrder {
                    outputs[pass] = try SwiftCloneDetectorAdapter.read(draft.report(of: pass), pass: pass)
                }
                return CloneMapper(measured: library.measured).mapping(of: Self.cloneRun(outputs))
            }

            #expect(Self.checkClones(draft, outcome: outcome, library: library))
            #expect(throws: AdapterError.self) { try outcome.get() }
        }
        #expect(Self.cloneLabels(of: atZero).contains(Self.belowOne))
        #expect(Self.cloneLabels(of: backwards).contains(Self.inverted))
    }

    @Test("""
        the clone path's check detects a planted defect: B25's 04b undone with a wrapping add, which moves a \
        saturated column to Int.min + 2
        """)
    func cloneCheckDetectsWrappingShift() throws {
        let library = try Library()
        defer { library.remove() }
        let draft = Self.saturatingClones
        var outputs: [CloneDetectorPass: CloneDetectorOutput] = [:]
        for pass in CloneDetectorPass.runOrder {
            outputs[pass] = try SwiftCloneDetectorAdapter.read(draft.report(of: pass), pass: pass)
        }
        let mapping = try #require(CloneMapper(measured: library.measured).mapping(of: Self.cloneRun(outputs)))

        PlantedDefect.expectDetected("04b undone with a wrapping add", sourceLocation: #_sourceLocation) {
            Self.checkClones(
                draft,
                outcome: .success(Self.wrappingShift(mapping, draft: draft)),
                library: library
            )
        }
    }
}

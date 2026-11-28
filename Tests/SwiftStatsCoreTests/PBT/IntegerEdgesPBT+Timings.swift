//
//  IntegerEdgesPBT+Timings.swift
//  SwiftStatsCoreTests
//
//  P15.1's timing path: the build's standard error read as the collector
//  reads it (`BuildOutputReader.read(stderr:log:)`), its entries mapped by
//  `TimingMapper`, every time, line and column an integer edge. A time of
//  `Int.max - 3` milliseconds or more has more than twelve whole digits,
//  so its line is counted unparsed (B1); any other line is an entry at
//  its place, mapped onto `first()` at 1:1 and onto the file anywhere
//  else, each record's and attachment's time summed and rounded once, and
//  the totals counting every entry. Its examples, and a meta-test that
//  feeds a planted defect's reading (B1's bound undone with a wrapping
//  multiply) to its check.
//

import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P15.1's timing path.
extension IntegerEdgesPBT {
    /// What reading timing lines and mapping their entries gave.
    struct ReadTimings {
        /// The build output read.
        let output: BuildOutput
        /// What mapping its entries gave.
        let mapped: TimingMapper.Mapped
    }

    /// The timing path's base runs, over the engine's 100: reading and
    /// mapping two lines costs tens of microseconds. The rarest
    /// antecedent, an entry read at 1:1, comes in 129 of the meta-test's
    /// 1,000 drafts (design D14: `(1 - 0.129)^150`, about 1 * 10^-9, is
    /// the most a run misses it; 100 runs would miss it about 10^-6 of the
    /// time).
    static let timingRuns = 150
    /// The antecedents the timing path must reach at least once each.
    static let timingAntecedents = [mapped, failed, unknown, largest, zero]
    /// Hundredths of a millisecond in one.
    static let hundredthsPerMillisecond = 100

    /// A line of 1 ms at 1:1 and one of `Int.max` ms at `Int.max`:0.
    static let largestTimings = TimingEdgeDraft(lines: [
        TimingEdgeDraft.Line(milliseconds: 1, line: 1, column: 1),
        TimingEdgeDraft.Line(milliseconds: Int.max, line: Int.max, column: 0)
    ])

    /// Whether `line` is read as an entry: its time has at most twelve
    /// whole digits, as `BuildLineGrammar.wholeDigits` bounds it.
    static func isRead(_ line: TimingEdgeDraft.Line) -> Bool {
        String(line.milliseconds).count <= BuildLineGrammar.wholeDigits
    }

    /// Whether `line` lies at the one edge point a record holds, 1:1.
    static func isPlaced(_ line: TimingEdgeDraft.Line) -> Bool {
        line.line == 1 && line.column == 1
    }

    /// The classes `draft` falls in, for the timing path's tally and the
    /// generator's meta-test.
    static func timingLabels(of draft: TimingEdgeDraft) -> [String] {
        let read = draft.lines.filter(isRead)
        return [
            (read.count < draft.lines.count, failed),
            (read.contains(where: isPlaced), mapped),
            (read.contains { isPlaced($0) == false }, unknown)
        ]
        .filter(\.0)
        .map(\.1) + edgeLabels(draft.lines.flatMap { [$0.milliseconds, $0.line, $0.column] })
    }

    /// Whether `read`, what `draft`'s standard error gave on `library`, is
    /// what the reader's and the mapper's rules give: each line read as its entry or counted unparsed, the entries
    /// on `first()` at 1:1 and on the file elsewhere, each one's whole
    /// milliseconds summed, and the totals counting them all. Records an
    /// issue for each law that fails.
    static func checkTimings(_ draft: TimingEdgeDraft, read: ReadTimings, library: Library) -> Bool {
        let root = library.root
        let firstKey = library.firstKey
        let lines = draft.lines.filter(isRead)
        let expected = lines.map { line in
            TimingEntry(
                kind: .function,
                hundredths: line.milliseconds * hundredthsPerMillisecond,
                place: BuildPlace(path: root + "/" + IntegerEdgeGen.plainFile, line: line.line, column: line.column),
                declaration: TimingEdgeDraft.declaration
            )
        }
        let onRecord = lines.filter(isPlaced).map(\.milliseconds)
        let onFile = lines.filter { isPlaced($0) == false }.map(\.milliseconds)
        let records = onRecord.isEmpty
            ? [] : [BuildRecordTiming(key: firstKey, milliseconds: onRecord.reduce(0, +), slowestExpression: nil)]
        let attachments = onFile.isEmpty ? [] : [
            BuildAttachment(
                owner: IntegerEdgeGen.plainFile,
                attachedTo: .file,
                milliseconds: onFile.reduce(0, +),
                slowestExpression: nil
            )
        ]
        let totals = BuildTotals(
            functionEntries: lines.count,
            expressionEntries: 0,
            milliseconds: (onRecord + onFile).reduce(0, +)
        )
        let unparsed = draft.lines.count - lines.count
        return holds(
            [
                (read.output.entries == expected, "reads the entries \(read.output.entries), expected \(expected)"),
                (read.output.unparsedTimingLines == unparsed, "counts \(read.output.unparsedTimingLines) unparsed"),
                (read.mapped.records == records, "maps onto records \(read.mapped.records), expected \(records)"),
                (
                    read.mapped.attachments == attachments,
                    "attaches \(read.mapped.attachments), expected \(attachments)"
                ),
                (read.mapped.totals == totals, "totals \(read.mapped.totals), expected \(totals)")
            ],
            subject: "mapping the timing lines"
        )
    }

    /// Counts in `tally` what `read` shows: an entry on a record, and one
    /// that isn't.
    static func tallyTimings(_ read: ReadTimings, in tally: AntecedentTally) {
        if read.mapped.records.isEmpty == false {
            tally.fire(mapped)
        }
        if read.mapped.attachments.isEmpty == false {
            tally.fire(unknown)
        }
    }

    /// `draft`'s standard error read with B1's twelve-digit bound undone
    /// and a wrapping multiply in its place, then mapped on `library`: the
    /// planted defect.
    static func wrappingTimes(_ draft: TimingEdgeDraft, onto library: Library) -> ReadTimings {
        let entries = draft.lines.map { line in
            TimingEntry(
                kind: .function,
                hundredths: line.milliseconds &* hundredthsPerMillisecond,
                place: BuildPlace(
                    path: library.root + "/" + IntegerEdgeGen.plainFile,
                    line: line.line,
                    column: line.column
                ),
                declaration: TimingEdgeDraft.declaration
            )
        }
        let output = BuildOutput(
            entries: entries,
            diagnostics: [],
            escapedLines: 0,
            unparsedTimingLines: 0,
            otherWarningLines: 0
        )
        return ReadTimings(output: output, mapped: library.timingMapper.map(entries))
    }

    // MARK: P15.1, timings

    /// Invariant: type-check timing lines whose times, lines and columns are
    /// integer edges are each read as their entry or, past twelve whole
    /// digits, counted unparsed; the entries map onto the record holding
    /// their place, else its file, summed per record and attachment and in
    /// the totals, and nothing traps.
    /// Why it holds: `BuildLineGrammar`'s header and `wholeDigits` (B1),
    /// `BuildOutputReader`'s (a refused timing line on the standard error
    /// is counted), and `TimingMapper`'s (placed by position; sums stop at
    /// `Int.max`, B18) (M7 design §6.1, §6.2).
    /// Why it might not: two function-body lines in the scanned file,
    /// `first()` alone holding an edge point, 1:1, as `libraryIsAsStated`
    /// pins; sums of 0 and 1 ms stay far from `Int.max`, so B18's
    /// saturation is pinned by `TimingFigureTests+Saturation` alone.
    /// Oracle: postconditions from the rules above, sums worked out apart
    /// from the mapper; planted defects: B1's bound removed (a trapping
    /// multiply, detected as a trap), a number of 0 refused, and
    /// (meta-test) B1's bound undone with a wrapping multiply, each
    /// detected.
    /// Tier: Strict (stop-ship).
    @Test(
        """
        timing lines at the integer edges are read or counted unparsed, their entries mapped onto the record or \
        the file, and nothing traps
        """,
        .timeLimit(PBTBudget.timeLimit)
    )
    func timingEdgesMap() async throws {
        let library = try Library()
        defer { library.remove() }
        let mapper = library.timingMapper
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.timingRuns), input: IntegerEdgeGen.timings) { draft in
            PBTTrace.note(draft)
            Self.timingLabels(of: draft).filter { $0 != Self.mapped && $0 != Self.unknown }.forEach(tally.fire)
            let output = BuildOutputReader.read(stderr: draft.standardError(root: library.root), log: Data())
            let read = ReadTimings(output: output, mapped: mapper.map(output.entries))
            Self.tallyTimings(read, in: tally)
            if Self.checkTimings(draft, read: read, library: library) == false {
                PBTTrace.firstFailure(draft, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.timingAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("a 1 ms line at 1:1 maps onto first(), and an Int.max ms line at Int.max:0 is counted unparsed")
    func largestTimingsMap() throws {
        let library = try Library()
        defer { library.remove() }
        let draft = Self.largestTimings

        let output = BuildOutputReader.read(stderr: draft.standardError(root: library.root), log: Data())
        let read = ReadTimings(output: output, mapped: library.timingMapper.map(output.entries))

        #expect(Self.checkTimings(draft, read: read, library: library))
        #expect(read.output.unparsedTimingLines == 1)
        #expect(read.mapped.records.map(\.key) == ["Lib::func first() -> Int"])
    }

    @Test("lines of 0 ms at 0:0 and 1 ms at 1:Int.max both map onto the file, and nothing onto first()")
    func edgePlacesOnFile() throws {
        let library = try Library()
        defer { library.remove() }
        let draft = TimingEdgeDraft(lines: [
            TimingEdgeDraft.Line(milliseconds: 0, line: 0, column: 0),
            TimingEdgeDraft.Line(milliseconds: 1, line: 1, column: Int.max)
        ])

        let output = BuildOutputReader.read(stderr: draft.standardError(root: library.root), log: Data())
        let read = ReadTimings(output: output, mapped: library.timingMapper.map(output.entries))

        #expect(Self.checkTimings(draft, read: read, library: library))
        #expect(read.mapped.records.isEmpty)
        #expect(read.mapped.attachments.map(\.milliseconds) == [1])
    }

    @Test("the timing path's check detects a planted defect: B1's bound undone with a wrapping multiply")
    func timingCheckDetectsWrappingTimes() throws {
        let library = try Library()
        defer { library.remove() }
        let draft = Self.largestTimings

        PlantedDefect.expectDetected("B1's bound undone with a wrapping multiply", sourceLocation: #_sourceLocation) {
            Self.checkTimings(draft, read: Self.wrappingTimes(draft, onto: library), library: library)
        }
    }
}

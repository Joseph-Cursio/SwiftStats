//
//  IntegerEdgesPBT+Outskirts.swift
//  SwiftStatsCoreTests
//
//  P15.1's dead-code path: an outskirts run read as the collector reads it
//  (`PeripheryOutput.decode(_:run:context:)`), then joined to the scan by
//  `DeadCodeMapper`, every location's line and column an integer edge.
//  A location whose line or column is 0 isn't `path:line:column`, and the
//  run fails naming the first such entry; otherwise every entry is kept
//  with its numbers, an unused free function at 1:1 covers `first()` by
//  its location and is listed on it, the lower ordinal keeping it, and
//  one anywhere else covers nothing and is listed on the file. Its
//  examples, and a meta-test that feeds a planted defect's report (a
//  location's numbers read as `Int32`, clamping) to its check.
//

import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P15.1's dead-code path.
extension IntegerEdgesPBT {
    /// What reading an outskirts run and joining it gave: the report, or
    /// the failure reading the run gave.
    typealias DeadCodeOutcome = Result<DeadCodeReport, any Error>

    /// The dead-code path's base runs, the engine's 100: two entries cost
    /// tens of microseconds. The rarest antecedent, an entry at 1:1 in a
    /// run that reads, comes in 189 of the meta-test's 1,000 runs (design
    /// D14: `(1 - 0.189)^100`, about 8 * 10^-10, is the most a run misses
    /// it).
    static let deadCodeRuns = 100
    /// The root the run's paths lie under: it doesn't exist, so making a
    /// path real touches nothing on disk.
    static let absentRoot = "/NoSuchIntegerEdgePackage"
    /// The antecedents the dead-code path must reach at least once each.
    static let deadCodeAntecedents = [mapped, failed, unknown, largest, zero]

    /// A run of an entry at 1:1 and one at `Int.max`:`Int.max - 3`.
    static let largestOutskirts = OutskirtsEdgeDraft(locations: [
        OutskirtsEdgeDraft.Location(line: 1, column: 1),
        OutskirtsEdgeDraft.Location(line: Int.max, column: Int.max - IntegerEdgeGen.belowMaximum)
    ])

    /// Whether `location` is the one edge point a record holds, 1:1.
    static func isPlaced(_ location: OutskirtsEdgeDraft.Location) -> Bool {
        location.line == 1 && location.column == 1
    }

    /// The ordinal of the first entry of `draft` whose line or column is
    /// 0, which fails the run; nil when there is none.
    static func faultyEntry(of draft: OutskirtsEdgeDraft) -> Int? {
        draft.locations.firstIndex { $0.line < 1 || $0.column < 1 }.map { $0 + 1 }
    }

    /// The classes `draft` falls in, for the dead-code path's tally and the
    /// generator's meta-test.
    static func deadCodeLabels(of draft: OutskirtsEdgeDraft) -> [String] {
        let edges = edgeLabels(draft.locations.flatMap { [$0.line, $0.column] })
        guard faultyEntry(of: draft) == nil else {
            return [failed] + edges
        }
        return [
            (draft.locations.contains(where: isPlaced), mapped),
            (draft.locations.contains { isPlaced($0) == false }, unknown)
        ]
        .filter(\.0)
        .map(\.1) + edges
    }

    /// What classing entries needs, for the package of `library` under
    /// `absentRoot`, nothing changed and no index.
    static func outskirtsContext(_ library: Library) throws -> PeripheryOutput.Context {
        PeripheryOutput.Context(
            root: absentRoot,
            scratch: absentRoot + "/.swiftstats/index-build",
            package: try library.harness.package.describer.describePackage(at: library.harness.package.root),
            modules: ["Lib": "Lib"],
            files: Dictionary(library.measured.files.map { ($0.path, $0.module) }) { first, _ in first },
            changedFiles: [],
            records: library.measured.records,
            localUSRs: []
        )
    }

    /// The scan the join maps onto: `library`'s.
    static func deadCodeScan(_ library: Library) -> IndexAdapter.Scan {
        let measured = library.measured
        return IndexAdapter.Scan(
            root: URL(fileURLWithPath: library.root),
            records: measured.records,
            types: measured.types,
            files: measured.files,
            targets: library.harness.targets,
            topLevelLines: measured.topLevelLines,
            fileScopedTypes: measured.fileScopedTypes,
            warnings: measured.warnings
        )
    }

    /// Whether `outcome`, what `draft`'s run gave on `library`, is what the
    /// reader's and the join's rules give: refused naming the first entry
    /// whose line or column is 0; else every entry a production
    /// declaration of the scanned file keeping its numbers, listed on
    /// `first()` at 1:1 and on the file elsewhere, `first()` covered by its
    /// location by the first entry at 1:1, its one line dead. Records an
    /// issue for each law that fails.
    static func checkDeadCode(_ draft: OutskirtsEdgeDraft, outcome: DeadCodeOutcome, library: Library) -> Bool {
        let subject = "joining the outskirts run"
        if let ordinal = faultyEntry(of: draft) {
            let named = "isn't path:line:column in entry \(ordinal) of the production run"
            guard case .failure(let error) = outcome else {
                return holds([(false, "reads a run whose entry \(ordinal) is at 0: \(outcome)")], subject: subject)
            }
            let law = (holds: "\(error)".hasSuffix(named), law: "refuses it as \(error), not naming entry \(ordinal)")
            return holds([law], subject: subject)
        }
        guard case .success(let report) = outcome else {
            return holds([(false, "fails to read the run: \(outcome)")], subject: subject)
        }
        let declarations = report.declarations
        let covering = draft.locations.firstIndex(where: isPlaced).map { $0 + 1 }
        let records = covering.map { ordinal in
            [DeadCodeRecord(key: library.firstKey, run: .production, declaration: ordinal, via: .location)]
        }
        let deadLines: [String: Int] = covering == nil ? [:] : ["Lib": 1]
        var laws = [
            (declarations.count == draft.locations.count, "lists \(declarations.count) declarations"),
            (report.records == (records ?? []), "covers \(report.records), expected \(records ?? [])"),
            (report.deadLines[DeadCodeRun.production.rawValue] == deadLines, "counts dead lines \(report.deadLines)")
        ]
        for (declaration, location) in zip(declarations, draft.locations) {
            let placed = isPlaced(location)
            laws += [
                (
                    (declaration.file, declaration.line, declaration.column, declaration.entryClass)
                        == (IntegerEdgeGen.plainFile, location.line, location.column, .production),
                    "reads \(location.line):\(location.column) as \(String(describing: declaration.file)) "
                        + "\(declaration.line):\(declaration.column), \(declaration.entryClass)"
                ),
                (
                    declaration.place == (placed ? .function : .file)
                        && declaration.owner == (placed ? library.firstKey : nil),
                    "lists \(location.line):\(location.column) on \(declaration.place) "
                        + "\(String(describing: declaration.owner))"
                )
            ]
        }
        return holds(laws, subject: subject)
    }

    /// Counts in `tally` what `outcome` shows: a declaration listed on a
    /// record, and one that isn't.
    static func tallyDeadCode(_ outcome: DeadCodeOutcome, in tally: AntecedentTally) {
        guard case .success(let report) = outcome else {
            return
        }
        if report.declarations.contains(where: { $0.place == .function }) {
            tally.fire(mapped)
        }
        if report.declarations.contains(where: { $0.place != .function }) {
            tally.fire(unknown)
        }
    }

    /// `draft`'s run as a reader taking a location's numbers as `Int32`
    /// would read it: refused for a number past `Int32.max`, otherwise
    /// `outcome`. The planted defect.
    static func int32Locations(_ draft: OutskirtsEdgeDraft, outcome: DeadCodeOutcome) -> DeadCodeOutcome {
        let fitsInt32 = { (location: OutskirtsEdgeDraft.Location) in
            Int32(exactly: location.line) != nil && Int32(exactly: location.column) != nil
        }
        guard let index = draft.locations.firstIndex(where: { fitsInt32($0) == false }) else {
            return outcome
        }
        let description = "JSON's \"location\" isn't path:line:column in entry \(index + 1) of the production run"
        return .failure(PeripheryOutput.FormatFailure(description: description))
    }

    // MARK: P15.1, dead code

    /// Invariant: an outskirts run whose locations are integer edges is
    /// refused naming the first entry at line or column 0; otherwise each
    /// entry keeps its numbers and is listed on the record holding its
    /// place, else its file, `first()` covered by the first unused free
    /// function at its position, and nothing traps.
    /// Why it holds: `PeripheryOutput`'s header and `fields(of:ordinal:run:)`
    /// (a location is `path:line:column` with a positive line and column,
    /// M7 design §5.3), and `DeadCodeMapper`'s and `DeadCodeRules`' (without
    /// the index a function by its name position; the lower ordinal keeps
    /// a record covered twice; §5.4).
    /// Why it might not: two unused free functions of `Lib`, in the scanned
    /// file, under a root that doesn't exist; `first()` holds 1:1 and no
    /// record or type holds another edge point, as `libraryIsAsStated`
    /// pins.
    /// Oracle: postconditions from the rules above; planted defects: a
    /// location's 0 taken as positive, a location's numbers read as
    /// `Int32` (in the reader, and as the meta-test's refusal), each
    /// detected.
    /// Tier: Strict (stop-ship).
    @Test(
        """
        an outskirts run at the integer edges is refused for a location at 0 or joined with every entry kept, \
        and nothing traps
        """,
        .timeLimit(PBTBudget.timeLimit)
    )
    func outskirtsEdgesMap() async throws {
        let library = try Library()
        defer { library.remove() }
        let context = try Self.outskirtsContext(library)
        let mapper = DeadCodeMapper(scan: Self.deadCodeScan(library), index: nil)
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.deadCodeRuns), input: IntegerEdgeGen.outskirts) { draft in
            PBTTrace.note(draft)
            Self.deadCodeLabels(of: draft).filter { $0 != Self.mapped && $0 != Self.unknown }.forEach(tally.fire)
            let outcome = DeadCodeOutcome {
                let data = try draft.data(root: Self.absentRoot)
                let entries = try PeripheryOutput.decode(data, run: .production, context: context)
                return mapper.report(PeripheryOutput(version: "3.28.0", retained: [], entries: entries))
            }
            Self.tallyDeadCode(outcome, in: tally)
            if Self.checkDeadCode(draft, outcome: outcome, library: library) == false {
                PBTTrace.firstFailure(draft, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.deadCodeAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("an unused free function at 1:1 covers first(), and one at Int.max:Int.max - 3 is listed on the file")
    func largestOutskirtsJoin() throws {
        let library = try Library()
        defer { library.remove() }
        let draft = Self.largestOutskirts

        let outcome = DeadCodeOutcome {
            let data = try draft.data(root: Self.absentRoot)
            let entries = try PeripheryOutput.decode(data, run: .production, context: Self.outskirtsContext(library))
            let mapper = DeadCodeMapper(scan: Self.deadCodeScan(library), index: nil)
            return mapper.report(PeripheryOutput(version: "3.28.0", retained: [], entries: entries))
        }

        #expect(Self.checkDeadCode(draft, outcome: outcome, library: library))
        let report = try outcome.get()
        #expect(report.declarations.map(\.place) == [.function, .file])
        #expect(report.declarations.map(\.line) == [1, Int.max])
    }

    @Test("two unused free functions at 1:1 both list on first(), and the first of them covers it")
    func coveredTwiceKeepsFirst() throws {
        let library = try Library()
        defer { library.remove() }
        let place = OutskirtsEdgeDraft.Location(line: 1, column: 1)
        let draft = OutskirtsEdgeDraft(locations: [place, place])

        let outcome = DeadCodeOutcome {
            let data = try draft.data(root: Self.absentRoot)
            let entries = try PeripheryOutput.decode(data, run: .production, context: Self.outskirtsContext(library))
            let mapper = DeadCodeMapper(scan: Self.deadCodeScan(library), index: nil)
            return mapper.report(PeripheryOutput(version: "3.28.0", retained: [], entries: entries))
        }

        #expect(Self.checkDeadCode(draft, outcome: outcome, library: library))
        #expect(try outcome.get().records.map(\.declaration) == [1])
    }

    @Test("a run whose second entry is at column 0 is refused, naming entry 2")
    func zeroColumnRefused() throws {
        let library = try Library()
        defer { library.remove() }
        let draft = OutskirtsEdgeDraft(locations: [
            OutskirtsEdgeDraft.Location(line: Int.max, column: 1),
            OutskirtsEdgeDraft.Location(line: 1, column: 0)
        ])

        let outcome = DeadCodeOutcome {
            let data = try draft.data(root: Self.absentRoot)
            let entries = try PeripheryOutput.decode(data, run: .production, context: Self.outskirtsContext(library))
            let mapper = DeadCodeMapper(scan: Self.deadCodeScan(library), index: nil)
            return mapper.report(PeripheryOutput(version: "3.28.0", retained: [], entries: entries))
        }

        #expect(Self.checkDeadCode(draft, outcome: outcome, library: library))
        #expect(throws: PeripheryOutput.FormatFailure.self) { try outcome.get() }
    }

    @Test("the dead-code path's check detects a planted defect: a location's numbers read as Int32")
    func deadCodeCheckDetectsInt32Locations() throws {
        let library = try Library()
        defer { library.remove() }
        let draft = Self.largestOutskirts
        let outcome = DeadCodeOutcome {
            let data = try draft.data(root: Self.absentRoot)
            let entries = try PeripheryOutput.decode(data, run: .production, context: Self.outskirtsContext(library))
            let mapper = DeadCodeMapper(scan: Self.deadCodeScan(library), index: nil)
            return mapper.report(PeripheryOutput(version: "3.28.0", retained: [], entries: entries))
        }

        PlantedDefect.expectDetected("a location's numbers read as Int32", sourceLocation: #_sourceLocation) {
            Self.checkDeadCode(draft, outcome: Self.int32Locations(draft, outcome: outcome), library: library)
        }
    }
}

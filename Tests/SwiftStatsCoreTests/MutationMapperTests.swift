import Foundation
@testable import SwiftStatsCore
import Testing

/// The mutation mapping on the Coverage fixture's recorded run (M6, design
/// §3): every mutant's anchor, place and owner, hand-checked against the
/// fixture's source, and what the report counts and records of the run.
@Suite("Mutation mapper")
struct MutationMapperTests {
    /// A mutant's key as SwiftMutator spells it, and where it went: its
    /// anchor (`-` for none), its place, and its owner or reason.
    private struct Expected: Equatable, CustomStringConvertible {
        /// The key, `path:line:column Operator`.
        let key: String
        /// `line:column place owner-or-reason`.
        let mapped: String

        /// The pair, for a failing expectation's message.
        var description: String {
            "\(key) → \(mapped)"
        }

        /// The expectation that `key` goes as `mapped` says.
        init(_ key: String, _ mapped: String) {
            self.key = key
            self.mapped = mapped
        }

        /// Where `mutant` went, written as an expectation is.
        init(_ mutant: Mutant) {
            let anchor = mutant.anchor.map { "\($0.line):\($0.column)" } ?? "-"
            self.init(
                "\(mutant.path):\(mutant.line):\(mutant.column) \(mutant.operatorID)",
                "\(anchor) \(mutant.place.rawValue) \(mutant.owner ?? mutant.reason ?? "-")"
            )
        }
    }

    /// The recorded run's 33 tested and 10 not-covered mutants, each
    /// checked by hand against the fixture's source: `main.swift`'s line 5
    /// is in `exeHelper`'s body, not on a statement line; the lazy
    /// property's closure (`Accessors.swift:12:45`) is attached to `Box`,
    /// the global's closure (`Attached.swift:2:36`) to its file, and the
    /// default argument's closure (`:5:58`) folds into `withDefault`; the
    /// byte order mark shifts `Bom.swift:1:33` to 1:36; nested functions
    /// take their own mutants; `||` (`Nested.swift:18:20`) starts at its
    /// point, the `>` swaps inside the closure fold into `anyLarge`, and
    /// the `false` constant one past the closure's `}` (`:18:51`) is
    /// anchored on that `}`; the nested package's mutant is dropped and the
    /// excluded file's unmapped.
    private static let expected = [
        Expected("Nested/Helper/Sources/Helper/Helper.swift:3:5 ReplaceReturnValue", "- dropped otherPackage"),
        Expected("Sources/Exe/main.swift:5:5 ReplaceReturnValue", "5:5 record Exe::func exeHelper(_: Int) -> Int"),
        Expected(
            "Sources/Exe/main.swift:5:11 ChangeArithmeticOperator",
            "5:11 record Exe::func exeHelper(_: Int) -> Int"
        ),
        Expected(
            "Sources/Probe/Accessors.swift:6:34 ReplaceReturnValue",
            "6:34 record Probe::Box::var both: Int { get }"
        ),
        Expected(
            "Sources/Probe/Accessors.swift:8:78 ChangeArithmeticOperator",
            "8:78 record Probe::Box::var watched { didSet }"
        ),
        Expected(
            "Sources/Probe/Accessors.swift:10:31 ReplaceReturnValue",
            "10:31 record Probe::Box::var doubled: Int { get }"
        ),
        Expected(
            "Sources/Probe/Accessors.swift:10:39 ChangeArithmeticOperator",
            "10:39 record Probe::Box::var doubled: Int { get }"
        ),
        Expected("Sources/Probe/Accessors.swift:12:45 ChangeArithmeticOperator", "12:45 type Probe::Box"),
        Expected(
            "Sources/Probe/Accessors.swift:14:49 ReplaceReturnValue",
            "14:49 record Probe::Box::subscript(_: Int) -> Int / { get }"
        ),
        Expected(
            "Sources/Probe/Accessors.swift:14:92 ChangeArithmeticOperator",
            "14:92 record Probe::Box::subscript(_: Int) -> Int / { set }"
        ),
        Expected(
            "Sources/Probe/Attached.swift:2:36 ChangeArithmeticOperator",
            "2:36 file Sources/Probe/Attached.swift"
        ),
        Expected(
            "Sources/Probe/Attached.swift:5:58 ChangeArithmeticOperator",
            "5:58 record Probe::func withDefault(_: (Int) -> Int) -> Int"
        ),
        Expected(
            "Sources/Probe/Attached.swift:6:5 ReplaceReturnValue",
            "6:5 record Probe::func withDefault(_: (Int) -> Int) -> Int"
        ),
        Expected(
            "Sources/Probe/Attached.swift:17:5 ReplaceReturnValue",
            "17:5 record Probe::func firstSecret() -> Int"
        ),
        Expected("Sources/Probe/Bom.swift:1:33 ReplaceReturnValue", "1:36 record Probe::func bomFirst() -> Int"),
        Expected("Sources/Probe/Bom.swift:5:5 ReplaceReturnValue", "5:5 record Probe::func bomSecond() -> Int"),
        Expected(
            "Sources/Probe/Counter.swift:11:34 ChangeArithmeticOperator",
            "11:34 record Probe::Counter::func add(_: [Int])"
        ),
        Expected(
            "Sources/Probe/Counter.swift:16:9 ReplaceReturnValue",
            "16:9 record Probe::Counter::func doubled() -> Int"
        ),
        Expected(
            "Sources/Probe/Counter.swift:22:5 ReplaceReturnValue",
            "22:5 record Probe::func twice(_: Int) -> Int @ Sources/Probe/Counter.swift"
        ),
        Expected(
            "Sources/Probe/Counter.swift:22:11 ChangeArithmeticOperator",
            "22:11 record Probe::func twice(_: Int) -> Int @ Sources/Probe/Counter.swift"
        ),
        Expected("Sources/Probe/Counter.swift:27:5 ReplaceReturnValue", "27:5 record Probe::func onlyKit() -> Int"),
        Expected("Sources/Probe/Counter.swift:32:5 ReplaceReturnValue", "32:5 record Probe::func neverCalled() -> Int"),
        Expected("Sources/Probe/Dependency.swift:5:5 ReplaceReturnValue", "5:5 record Probe::func fromHelper() -> Int"),
        Expected("Sources/Probe/Excluded.swift:3:5 ReplaceReturnValue", "- unmapped excluded"),
        Expected(
            "Sources/Probe/Generated.swift:3:5 ReplaceReturnValue",
            "3:5 record Probe::func generatedHelper() -> Int"
        ),
        Expected(
            "Sources/Probe/Nested.swift:4:9 ReplaceReturnValue",
            "4:9 record Probe::func outer(_: Bool) -> Int / func inner(_: Int) -> Int"
        ),
        Expected(
            "Sources/Probe/Nested.swift:4:15 ChangeArithmeticOperator",
            "4:15 record Probe::func outer(_: Bool) -> Int / func inner(_: Int) -> Int"
        ),
        Expected("Sources/Probe/Nested.swift:6:8 NegateConditional", "6:8 record Probe::func outer(_: Bool) -> Int"),
        Expected("Sources/Probe/Nested.swift:7:16 ReplaceReturnValue", "7:16 record Probe::func outer(_: Bool) -> Int"),
        Expected(
            "Sources/Probe/Nested.swift:14:53 ReplaceReturnValue",
            "14:53 record Probe::func sameLine() -> Int / func one() -> Int"
        ),
        Expected("Sources/Probe/Nested.swift:14:65 ReplaceReturnValue", "14:65 record Probe::func sameLine() -> Int"),
        Expected(
            "Sources/Probe/Nested.swift:18:5 ReplaceBooleanValue",
            "18:5 record Probe::func anyLarge(_: [Int]) -> Bool"
        ),
        Expected(
            "Sources/Probe/Nested.swift:18:20 ChangeLogicalConnector",
            "18:20 record Probe::func anyLarge(_: [Int]) -> Bool"
        ),
        Expected(
            "Sources/Probe/Nested.swift:18:44 RelationalBoundary",
            "18:44 record Probe::func anyLarge(_: [Int]) -> Bool"
        ),
        Expected(
            "Sources/Probe/Nested.swift:18:44 RelationalOperatorReplacement",
            "18:44 record Probe::func anyLarge(_: [Int]) -> Bool"
        ),
        Expected(
            "Sources/Probe/Nested.swift:18:51 ReplaceBooleanValue",
            "18:50 record Probe::func anyLarge(_: [Int]) -> Bool"
        ),
        Expected(
            "Sources/Probe/Overloads.swift:3:5 ReplaceReturnValue",
            "3:5 record Probe::func describe(_: Int) -> String"
        ),
        Expected(
            "Sources/Probe/Overloads.swift:8:5 ReplaceReturnValue",
            "8:5 record Probe::func describe(_: String) -> String"
        ),
        Expected(
            "Sources/Probe/Overloads.swift:13:32 ReplaceReturnValue",
            "13:32 record Probe::func mode() -> String #if DEBUG"
        ),
        Expected(
            "Sources/Probe/Overloads.swift:24:12 ReplaceReturnValue",
            "24:12 record Probe::func platform() -> String"
        ),
        Expected("Sources/Probe/Secrets.swift:9:5 ReplaceReturnValue", "9:5 record Probe::func secondSecret() -> Int"),
        Expected(
            "Sources/Probe/Wrappers.swift:8:15 ReplaceReturnValue",
            "8:15 record Probe::Clamped::var wrappedValue: Int { get }"
        ),
        Expected(
            "Sources/Probe/Wrappers.swift:36:5 ReplaceReturnValue",
            "36:5 record Probe::func lefts(_: [Int]) -> [Side]"
        )
    ]

    @Test("every mutant of the Coverage fixture's recorded run is anchored, placed and owned as its source says")
    func fixturePlaces() throws {
        let harness = try MappingHarness.coverage()
        defer { harness.remove() }
        let (results, suspects) = try MappingHarness.coverageRun()

        let report = harness.report(results, suspects: suspects)

        #expect(report.mutants.map(Expected.init) == Self.expected)
    }

    @Test("""
        the report counts the run's mutants per record, per attachment and over every mutant, drops the nested \
        package's, unmaps the excluded file's, and lists the run's Swift files, production ones as tested
        """)
    func fixtureCounts() throws {
        let harness = try MappingHarness.coverage()
        defer { harness.remove() }
        let (results, suspects) = try MappingHarness.coverageRun()

        let report = harness.report(results, suspects: suspects)

        #expect(report.everyMutant == MutationTotals(
            counts: MutationCounts(
                killed: 31,
                crashKills: 0,
                survived: 2,
                noCoverage: 0,
                timedOut: 0,
                notCovered: 10,
                buildErrors: 0,
                suspectOnly: 0,
                judgedKills: 31
            ),
            dropped: 1,
            unmapped: 1
        ))
        #expect(report.dropped == MutationDropped(
            build: 0,
            outsideRoot: 0,
            testFiles: 0,
            otherLanguage: 0,
            otherPackage: 1
        ))
        #expect(report.unmapped == ["excluded": 1])
        let anyLarge = try #require(report.records.first { $0.key == "Probe::func anyLarge(_: [Int]) -> Bool" })
        #expect(anyLarge.counts.killed == 2 && anyLarge.counts.survived == 1 && anyLarge.counts.notCovered == 2)
        #expect(anyLarge.killingTests == ["nesting()"])
        #expect(report.records.count == Set(report.mutants.filter { $0.place == .record }.compactMap(\.owner)).count)
        #expect(report.records.map(\.key) == report.records.map(\.key).sorted())
        #expect(report.attachments.map { "\($0.attachedTo.rawValue) \($0.owner) \($0.counts.killed)" } == [
            "file Sources/Probe/Attached.swift 1",
            "type Probe::Box 1"
        ])
        let tested = report.files.filter { $0.disposition == .tested }.map(\.path)
        #expect(report.files.count == 20)
        #expect(tested == [
            "Sources/Exe/main.swift", "Sources/Probe/Accessors.swift", "Sources/Probe/Attached.swift",
            "Sources/Probe/Bom.swift", "Sources/Probe/Counter.swift", "Sources/Probe/Dependency.swift",
            "Sources/Probe/Excluded.swift", "Sources/Probe/Generated.swift", "Sources/Probe/Nested.swift",
            "Sources/Probe/Overloads.swift", "Sources/Probe/Secrets.swift", "Sources/Probe/Wrappers.swift",
            "Sources/Unlinked/Unlinked.swift"
        ])
        #expect(report.files.filter { $0.disposition == .untested }.allSatisfy { $0.run == nil })
        #expect(report.files.allSatisfy { $0.sha256 == results.tree[$0.path] && $0.changedTest == false })
    }

    @Test("""
        the run is recorded with its build, the commit it tested, how it ended and its header's facts, and the \
        results are dated when it started
        """)
    func fixtureRun() throws {
        let harness = try MappingHarness.coverage()
        defer { harness.remove() }
        let (results, suspects) = try MappingHarness.coverageRun()

        let kept = ".swiftstats/mutation/runs/ab/results.jsonl"
        let report = harness.report(results, suspects: suspects, resultsFile: kept)

        let run = try #require(report.runs.first)
        #expect(report.runs.count == 1)
        #expect(report.collectedAt == MappingHarness.coverageStartedAt)
        #expect(report.complete && report.listsNotCovered && report.mode == .full && report.base == nil)
        #expect(run.ordinal == 0 && run.startedAt == MappingHarness.coverageStartedAt)
        #expect(run.identity == "sha256:\(MutationRunTests.recordedBuild)")
        #expect(run.commit == "c1" && run.dirty == false && run.mode == .full && run.since == nil)
        #expect(run.endReason == "finished" && run.endedAt == "2026-11-21T16:40:45.356Z")
        #expect(run.resultsFile == kept && run.resultsSHA256 == results.sha256)
        #expect(run.formatVersions == [4] && run.sessions == 1 && run.carriedFrom == nil)
        #expect(run.mutantsDiscovered == 33 && run.mutantsDropped == 2 && run.workers == 1 && run.timeoutSeconds == 20)
        #expect(run.toolchain == "Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1)")
        #expect(run.testExecutableSHA256 == nil && run.sdkEnvironment == nil)
        #expect(run.suspectsJudged == JSONFlag(suspects.suspectsChecked))
        #expect(report.mutants.allSatisfy { $0.run == 0 && $0.carried == false })
    }
}

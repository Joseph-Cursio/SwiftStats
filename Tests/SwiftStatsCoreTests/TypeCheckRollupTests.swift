//
//  TypeCheckRollupTests.swift
//  SwiftStatsCoreTests
//
//  The type-check roll-ups (M7, design §6.2, §6.4) on a small library and
//  hand-written entries mapped as a scan maps them: totals that add the
//  entries on records not nested in a body, on types and on files, in
//  hundredths rounded once per scope; maxima and records timed over every
//  record, nested ones included, records only; production and tests
//  parts, a test target's type counting for tests; none when the build
//  didn't run, and no maximum where no record has one; the metrics
//  attributed to the `build` collector; and a scope's total that stops at
//  `Int.max` hundredths instead of trapping.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// The type-check roll-ups, on a small library and hand-written entries.
@Suite("Type-check roll-ups")
struct TypeCheckRollupTests {
    /// A scan of the small library and its entries' mapping.
    private struct Mapped {
        /// The scan, without build results.
        let report: ScanReport
        /// The entries, mapped.
        let timings: TimingMapper.Mapped

        /// The build report the mapping gives, through the store's rows.
        var build: BuildReport {
            BuildRows.normalized(BuildReport(
                complete: true,
                records: timings.records,
                attachments: timings.attachments,
                unmapped: timings.unmapped,
                dropped: timings.dropped,
                totals: timings.totals,
                changedFiles: 0,
                unparsedTimingLines: 0,
                escapedLines: 0,
                otherWarningLines: 0,
                warningsDropped: 0,
                warningsUnmapped: 0,
                pluginWarnings: 0
            ))
        }

        /// The scan with the build attached as a scan attaches it.
        var rolled: ScanReport {
            let totals = TypeCheckTotals(
                counted: timings.counted,
                targets: report.targets,
                records: report.records,
                files: report.files
            )
            return report.with(build: build, totals: totals, status: TypeCheckRollupTests.ran)
        }
    }

    /// A hand-written timing entry.
    private struct Entry {
        /// The file, relative to the package root.
        let file: String
        /// Function body or expression.
        let kind: TimingEntry.Kind
        /// Its time, in hundredths of a millisecond.
        let hundredths: Int
        /// Its line.
        let line: Int
        /// Its UTF-8 column.
        let column: Int

        /// Creates an entry. Fields are documented on their properties.
        init(_ file: String, _ kind: TimingEntry.Kind, _ hundredths: Int, _ line: Int, _ column: Int) {
            self.file = file
            self.kind = kind
            self.hundredths = hundredths
            self.line = line
            self.column = column
        }
    }

    /// The library: a function, a function holding a local function and a
    /// type with a stored property.
    private static let library = """
        public func first() -> Int { 1 }
        public func outer() -> Int {
            func inner() -> Int { 1 }
            return inner()
        }
        public struct Box {
            public var stored = 1
        }

        """
    /// The test target: a type with a stored property, a helper and a
    /// function holding only an expression entry.
    private static let tests = """
        struct Fixture {
            var value = 1
        }
        func helper() -> Int { 2 }
        func onlyExpression() -> Int { 3 }

        """
    /// The library's file.
    private static let libraryFile = "Sources/Lib/Lib.swift"
    /// The test target's file.
    private static let testsFile = "Tests/LibTests/LibTests.swift"
    /// The `build` collector, ran.
    static let ran = CollectorStatus(name: BuildAdapter.name, state: .ran, version: nil, reason: nil, options: [])

    /// The entries, in hundredths, by file, kind, line and column: `first`
    /// 0.40 twice (1 ms); `outer` 1.40 (1 ms) with a 3 ms expression; its
    /// local `inner` 9.40 with a 7 ms expression, nested in a body; `Box`'s
    /// stored property 0.30 with a 15 ms expression, on the type; the test
    /// target's `Fixture` 0.45 on its type, `helper` 0.49 (0 ms) and a 2 ms
    /// expression on `onlyExpression`.
    private static let entries = [
        Entry(libraryFile, .function, 40, 1, 13),
        Entry(libraryFile, .function, 40, 1, 13),
        Entry(libraryFile, .function, 140, 2, 13),
        Entry(libraryFile, .expression, 300, 2, 20),
        Entry(libraryFile, .function, 940, 3, 10),
        Entry(libraryFile, .expression, 700, 3, 27),
        Entry(libraryFile, .function, 30, 7, 16),
        Entry(libraryFile, .expression, 1_500, 7, 25),
        Entry(testsFile, .function, 45, 2, 9),
        Entry(testsFile, .function, 49, 4, 6),
        Entry(testsFile, .expression, 200, 5, 32)
    ]

    /// The small library scanned, and `entries` mapped onto it.
    private static func mapped(_ entries: [Entry]) throws -> Mapped {
        let package = try TemporaryPackage([libraryFile: library, testsFile: tests])
        defer { package.remove() }
        let report = try SnapshotHarness.scan(package, commit: nil).report
        let targets = TargetResolver.resolve(try package.describer.describePackage(at: package.root))
        let measured = PackageScanner.measure(targets, root: package.root, configuration: SwiftStatsConfiguration())
        let root = BuildFixture.realPath(package.root)
        let mapper = TimingMapper(measured: measured, root: root, build: root + "/.build", changedFiles: [])
        let timed = entries.map { entry in
            TimingEntry(
                kind: entry.kind,
                hundredths: entry.hundredths,
                place: BuildPlace(path: root + "/" + entry.file, line: entry.line, column: entry.column),
                declaration: nil
            )
        }
        return Mapped(report: report, timings: mapper.map(timed))
    }

    /// The type-check figures of the roll-up `name` of `scope` in `report`.
    private static func figures(_ report: ScanReport, _ scope: RollupScope, _ name: String) throws -> TypeCheckRollup {
        try #require(report.rollups.first { $0.scope == scope && $0.name == name }?.typecheck)
    }

    @Test("""
        a scope's total adds the entries on its records not nested in a body, its types and its files in hundredths, \
        rounded once
        """)
    func totals() throws {
        let rolled = try Self.mapped(Self.entries).rolled

        // 0.80 + 1.40 + 0.30: `inner`'s 9.40 is inside `outer`'s entry; the records' own figures add to 2.
        #expect(try Self.figures(rolled, .module, "Lib").milliseconds.total == 3)
        // 0.45 + 0.49: the records' own figures add to 0.
        #expect(try Self.figures(rolled, .module, "LibTests").milliseconds.total == 1)
        // The build's own total rounds 3.44 once, so the parts can add to more.
        #expect(rolled.build?.totals.milliseconds == 3)
    }

    @Test("the maxima and the records timed take every record, nested ones included, and only records")
    func maxima() throws {
        let rolled = try Self.mapped(Self.entries).rolled
        let production = try Self.figures(rolled, .module, "Lib")
        let tested = try Self.figures(rolled, .module, "LibTests")

        // `inner`'s 9 and 7 ms are the largest; `Box`'s 15 ms expression is on a type.
        #expect(production.milliseconds.max == 9)
        #expect(production.slowestExpression.max == 7)
        #expect(production.functions.timed == 3)
        // `helper` is timed at 0 ms; `onlyExpression` has an expression only, so isn't timed.
        #expect(tested.milliseconds.max == 0)
        #expect(tested.slowestExpression.max == 2)
        #expect(tested.functions.timed == 1)
    }

    @Test("the production part holds the production modules, the tests part the test targets, their types included")
    func parts() throws {
        let rolled = try Self.mapped(Self.entries).rolled

        #expect(try Self.figures(rolled, .project, "production") == Self.figures(rolled, .module, "Lib"))
        #expect(try Self.figures(rolled, .project, "tests") == Self.figures(rolled, .module, "LibTests"))
        // `Fixture`'s 0.45 makes the tests part's 0.94 round to 1.
        #expect(try Self.figures(rolled, .project, "tests").milliseconds.total == 1)
    }

    @Test("""
        without a build no scope has figures; with one, a scope no record timed has a total and a count of 0 and \
        no maxima, never 0
        """)
    func nulls() throws {
        let mapped = try Self.mapped(Self.entries)
        let plain = mapped.rolled.with(build: nil, totals: .empty, status: Self.ran)
        let metrics = try plain.rollups.flatMap { try RollupMetrics.metrics(of: $0) }
        let typeOnly = try Self.mapped([Entry(Self.libraryFile, .function, 30, 7, 16)]).rolled
        let untimed = try Self.figures(typeOnly, .module, "LibTests")
        let paths = try RollupMetrics.metrics(of: try #require(typeOnly.rollups.first { $0.name == "LibTests" }))
            .map(\.path)
            .filter { $0.hasPrefix("typecheck.") }

        #expect(plain.rollups.allSatisfy { $0.typecheck == nil })
        #expect(metrics.contains { $0.path.hasPrefix("typecheck.") } == false)
        #expect(untimed.milliseconds.total == 0 && untimed.functions.timed == 0)
        #expect(untimed.milliseconds.max == nil && untimed.slowestExpression.max == nil)
        #expect(paths == ["typecheck.functions.timed", "typecheck.milliseconds.total"])
        #expect(try Self.figures(typeOnly, .module, "Lib").milliseconds.max == nil)
    }

    @Test("every type-check metric comes from the build collector, in the scan JSON under each roll-up's typecheck")
    func metrics() throws {
        let rolled = try Self.mapped(Self.entries).rolled
        let rollup = try #require(rolled.rollups.first { $0.scope == .module && $0.name == "Lib" })
        let named = try RollupMetrics.metrics(of: rollup).filter { $0.path.hasPrefix("typecheck.") }
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rollup)) as? [String: Any]
        let typecheck = json?["typecheck"] as? [String: [String: Int]]

        #expect(named.map(\.path) == [
            "typecheck.functions.timed", "typecheck.milliseconds.max", "typecheck.milliseconds.total",
            "typecheck.slowestExpression.max"
        ])
        #expect(named.allSatisfy { $0.collector == BuildAdapter.name })
        #expect(typecheck?["milliseconds"] == ["total": 3, "max": 9])
        #expect(typecheck?["slowestExpression"] == ["max": 7])
        #expect(typecheck?["functions"] == ["timed": 3])
    }

    @Test("a scope whose entries add past what an Int holds totals Int.max hundredths instead of trapping")
    func saturatingTotals() {
        let halfMaximal = Int.max / 2 + 1
        let totals = TypeCheckTotals(
            counted: [.type("Lib::Box"): halfMaximal, .type("Lib::Other"): halfMaximal],
            targets: [],
            records: [],
            files: []
        )
        // `Int.max` hundredths, 92233720368547758.07 ms.
        #expect(totals.total(.module, "Lib") == 92_233_720_368_547_758)
        #expect(totals.total(.project, "production") == 92_233_720_368_547_758)
    }
}

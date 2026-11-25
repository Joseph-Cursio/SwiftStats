import Foundation
@testable import SwiftStatsCore
import Testing

/// The `periphery` collector's results in the scan (M7, design §7, §9.2,
/// §10.3): the `deadCode` block, the dead-code roll-ups of each production
/// scope, every line ratio's dead lines, dead code excluded exactly when
/// outskirts ran, and the attribution of their metrics. A copy of the
/// Index fixture is scanned against its recorded build and dump, with a
/// fake outskirts acting out the recorded runs, failing, or absent.
/// Serialized, each scan on a thread of its own, as the index collector's
/// tests are.
@Suite("Dead-code results in the scan", .serialized)
struct DeadCodeResultsTests {
    /// The `roots` run's unused production declarations of `IndexCore` by
    /// kind: `neverCalled()` and `unusedHelper()`, `Unused`, its
    /// extension and the unused computed property.
    private static let coreUnused = [
        "enumCase": 0, "extension": 1, "function": 2, "import": 0, "other": 0, "parameter": 0, "property": 1, "type": 1
    ]

    /// Whether every roll-up of `report` lacks dead lines and dead-code
    /// counts, dead code not excluded.
    private static func lacksDeadCode(_ report: ScanReport) -> Bool {
        report.rollups.allSatisfy { rollup in
            rollup.deadCode == nil && rollup.tests.lineRatio.deadLines == nil
                && rollup.tests.lineRatio.deadCodeExcluded == false
        }
    }

    /// The roll-up `name` of `report`.
    private static func rollup(_ name: String, in report: ScanReport) throws -> Rollup {
        try #require(report.rollups.first { $0.name == name })
    }

    @Test("""
        a scan where outskirts didn't run, or failed, has no deadCode block, no dead-code roll-ups and no dead \
        lines in any line ratio, dead code not excluded
        """)
    func notExcludedWithoutOutskirts() async throws {
        try await IndexFixtureScan().run { _, outcome in
            #expect(outcome.statuses["periphery"]?.state == .skipped)
            #expect(outcome.report.deadCode == nil)
            #expect(Self.lacksDeadCode(outcome.report))
        }
        var scenario = try FakePeriphery.recorded()
        scenario.statuses[.production] = 1
        let fake = try FakePeriphery.make(scenario)
        defer { fake.remove() }
        var scan = try IndexFixtureScan()
        scan.extra = fake.configuration
        try await scan.run { _, outcome in
            #expect(outcome.statuses["periphery"]?.state == .failed)
            #expect(outcome.report.deadCode == nil)
            #expect(Self.lacksDeadCode(outcome.report))
        }
    }

    @Test("""
        once outskirts ran, every line ratio has the roots run's dead lines of the production modules it \
        measures against, dead code excluded, and each production scope its dead-code counts, attributed to \
        the periphery collector
        """)
    func rollupsOnceRan() async throws {
        let fake = try FakePeriphery.make(try FakePeriphery.recorded())
        defer { fake.remove() }
        var scan = try IndexFixtureScan()
        scan.extra = fake.configuration
        try await scan.run { _, outcome in
            let report = outcome.report
            #expect(report.rollups.contains { $0.tests.lineRatio.deadCodeExcluded == false } == false)
            let lines = Dictionary(uniqueKeysWithValues: report.rollups.map { rollup in
                (rollup.name, rollup.tests.lineRatio.deadLines)
            })
            #expect(lines == [
                "IndexApp": 0, "IndexCore": 22, "IndexCoreTests": 25, "IndexTool": 0, "IndexXCTests": 22,
                "index-kit": 3, "index-support": 0, "production": 25, "tests": 25
            ])
            let core = try Self.rollup("IndexCore", in: report)
            #expect(core.deadCode == DeadCodeRollup(
                records: 6,
                productionRecords: 7,
                unsized: 0,
                unused: Self.coreUnused
            ))
            let production = try Self.rollup("production", in: report)
            #expect(production.deadCode?.records == 7 && production.deadCode?.productionRecords == 9)
            #expect(try Self.rollup("index-support", in: report).deadCode?.productionRecords == 1)
            for name in ["IndexCoreTests", "IndexXCTests", "tests"] {
                #expect(try Self.rollup(name, in: report).deadCode == nil)
            }
            let metrics = Dictionary(uniqueKeysWithValues: try RollupMetrics.metrics(of: core).map { ($0.path, $0) })
            #expect(metrics["tests.lineRatio.deadLines"]?.collector == "periphery")
            #expect(metrics["tests.lineRatio.deadLines"]?.value == 22)
            #expect(metrics["deadCode.records"]?.collector == "periphery")
            #expect(metrics["deadCode.unused.function"]?.value == 2)
            #expect(metrics["tests.lineRatio.productionLines"]?.collector == "swiftstats")
            #expect(metrics["tests.lineRatio.deadCodeExcluded"] == nil)
        }
    }

    @Test("""
        the deadCode block survives attaching the history and the index, attaching none takes the roll-ups' \
        dead-code counts and dead lines away, and the block reads back as written
        """)
    func attachAndRoundTrip() async throws {
        let fake = try FakePeriphery.make(try FakePeriphery.recorded())
        defer { fake.remove() }
        var scan = try IndexFixtureScan()
        scan.extra = fake.configuration
        try await scan.run { _, outcome in
            let dead = try #require(outcome.report.deadCode)
            let history = outcome.report.with(history: nil, status: HistoryCollector.notRequested)
            #expect(history.deadCode == dead && history.rollups == outcome.report.rollups)
            let index = try #require(outcome.statuses["index"])
            #expect(outcome.report.with(index: outcome.report.index, status: index) == outcome.report)
            let status = try #require(outcome.statuses["periphery"])
            let cleared = outcome.report.with(deadCode: nil, status: status)
            #expect(cleared.deadCode == nil && Self.lacksDeadCode(cleared))
            #expect(cleared.with(deadCode: dead, status: status) == outcome.report)

            let data = try JSONEncoder().encode(dead)
            #expect(try JSONDecoder().decode(DeadCodeReport.self, from: data) == dead)
            let text = String(bytes: data, encoding: .utf8) ?? ""
            #expect(text.contains("\"class\":\"outsideRoot\"") && text.contains("\"via\":\"extension\""))
            #expect(text.contains("\"place\":\"unscanned\""))
            let unknowns = [("\"class\":\"outsideRoot\"", "\"class\":\"gone\""), ("\"via\":\"usr\"", "\"via\":\"x\"")]
            for (written, replacement) in unknowns {
                let unknown = Data(text.replacingOccurrences(of: written, with: replacement).utf8)
                #expect(throws: DecodingError.self) { try JSONDecoder().decode(DeadCodeReport.self, from: unknown) }
            }
        }
    }
}

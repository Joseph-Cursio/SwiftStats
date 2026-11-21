@testable import SwiftStatsCore
import Testing

/// Coverage roll-ups (M5, design §5): each production module's and the
/// project's production part's lines, regions, records and public
/// functions, with the project's unmapped entries and attachments; how the
/// numbers are named, which collector they come from and which way is
/// better.
@Suite("Coverage roll-ups")
struct CoverageRollupTests {
    /// The coverage roll-up named `name` of `scope` in `report`.
    private static func coverage(_ report: ScanReport, _ scope: RollupScope, _ name: String) -> CoverageRollup? {
        report.rollups.first { $0.scope == scope && $0.name == name }?.coverage
    }

    @Test("""
        the Coverage fixture's modules and production part count lines from the files' line data, regions from \
        records and attachments, records by data and public functions by their links, as worked out from its report
        """)
    func fixture() throws {
        let report = try CoverageFixture.report()

        let probe = try #require(Self.coverage(report, .module, "Probe"))
        #expect(probe.lines == CoverageRollup.Share(covered: 66, total: 80))
        #expect(probe.lines?.percent == 82.5)
        #expect(probe.regions == CoverageRollup.Share(covered: 41, total: 53))
        #expect(probe.regions?.percent == 77.36)
        #expect(probe.functions == CoverageRollup.Functions(withData: 35, executed: 27, noData: 1))
        #expect(probe.publicFunctions == CoverageRollup.PublicFunctions(
            total: 32,
            withCoverage: 31,
            linked: 23,
            unlinked: 8,
            reachedGenerically: 0,
            extensionMembers: 0,
            linkedTests: Distribution(Array(repeating: 0, count: 8) + Array(repeating: 1, count: 21) + [2, 2])
        ))
        #expect(probe.publicFunctions.linkedTests.median == 1 && probe.publicFunctions.linkedTests.max == 2)
        #expect(probe.unmapped == nil && probe.attached == nil)

        let exe = try #require(Self.coverage(report, .module, "Exe"))
        #expect(exe.lines == CoverageRollup.Share(covered: 3, total: 7))
        #expect(exe.regions == CoverageRollup.Share(covered: 1, total: 6))
        #expect(exe.functions == CoverageRollup.Functions(withData: 2, executed: 1, noData: 0))
        #expect(exe.publicFunctions.total == 0 && exe.publicFunctions.linkedTests.median == nil)

        let unlinked = try #require(Self.coverage(report, .module, "Unlinked"))
        #expect(unlinked.lines == nil && unlinked.regions == nil)
        #expect(unlinked.functions == CoverageRollup.Functions(withData: 0, executed: 0, noData: 1))
        #expect(unlinked.publicFunctions.total == 1 && unlinked.publicFunctions.withCoverage == 0)

        let production = try #require(Self.coverage(report, .project, "production"))
        #expect(production.lines == CoverageRollup.Share(covered: 69, total: 87))
        #expect(production.lines?.percent == 79.31)
        #expect(production.regions == CoverageRollup.Share(covered: 42, total: 59))
        #expect(production.functions == CoverageRollup.Functions(withData: 37, executed: 28, noData: 2))
        #expect(production.publicFunctions.total == 33 && production.publicFunctions.withCoverage == 31)
        #expect(production.unmapped == 1)
        #expect(production.attached == CoverageRollup.Attached(
            owners: 7,
            lines: CoverageRollup.Share(covered: 6, total: 9),
            regions: CoverageRollup.Share(covered: 8, total: 12)
        ))

        for name in ["ProbeTests", "SwiftTestKitTests"] {
            #expect(Self.coverage(report, .module, name) == nil)
        }
        #expect(Self.coverage(report, .project, "tests") == nil)
    }

    @Test("""
        a witness is reached generically, neither linked nor unlinked; an extension member counts within them too; \
        a subscript container is in neither record count; attachments belong to their type's or file's module
        """)
    func shapes() throws {
        let package = try TemporaryPackage(CoverageSamples.shapesFiles, targets: CoverageSamples.shapesTargets)
        defer { package.remove() }
        let scanned = try PackageScanner(describer: package.describer, tools: SnapshotHarness.noTools)
            .scan(packageAt: package.root)
        let records = scanned.records
        let coverage = try CoverageSamples.shapes(records: records)
        let builder = CoverageRollupBuilder(targets: scanned.targets, records: records, coverage: coverage)

        let lib = builder.rollup(of: ["Lib"], isProject: false)
        #expect(lib.lines == CoverageRollup.Share(covered: 5, total: 6))
        #expect(lib.lines?.percent == 83.33)
        #expect(lib.regions == CoverageRollup.Share(covered: 7, total: 9))
        #expect(lib.functions == CoverageRollup.Functions(withData: 5, executed: 4, noData: 1))
        #expect(lib.publicFunctions == CoverageRollup.PublicFunctions(
            total: 5,
            withCoverage: 4,
            linked: 2,
            unlinked: 1,
            reachedGenerically: 1,
            extensionMembers: 1,
            linkedTests: Distribution([3, 0, 1])
        ))
        let kit = builder.rollup(of: ["Kit"], isProject: false)
        #expect(kit.lines == CoverageRollup.Share(covered: 0, total: 1))
        #expect(kit.lines?.percent == 0)
        #expect(kit.regions?.percent == 50)
        let production = builder.rollup(of: ["Kit", "Lib"], isProject: true)
        #expect(production.lines?.percent == 71.43)
        #expect(production.regions == CoverageRollup.Share(covered: 8, total: 11))
        #expect(production.unmapped == 1)
        #expect(production.attached == CoverageRollup.Attached(
            owners: 2,
            lines: CoverageRollup.Share(covered: 1, total: 2),
            regions: CoverageRollup.Share(covered: 2, total: 3)
        ))
        let rolled = builder.rollups(scanned.rollups)
        #expect(rolled.first { $0.name == "LibTests" }?.coverage == nil)
        #expect(rolled.first { $0.name == "tests" }?.coverage == nil)
        #expect(rolled.first { $0.name == "Lib" }?.coverage == lib)
        #expect(rolled.first { $0.scope == .project && $0.name == "production" }?.coverage == production)
        #expect(scanned.rollups.allSatisfy { $0.coverage == nil })
    }

    @Test("a percentage keeps two decimal places, and a share of nothing has none rather than 0")
    func percentages() {
        #expect(CoverageRollup.Share.percent(covered: 2, total: 3) == 66.67)
        #expect(CoverageRollup.Share.percent(covered: 1, total: 3) == 33.33)
        #expect(CoverageRollup.Share.percent(covered: 1, total: 8) == 12.5)
        #expect(CoverageRollup.Share.percent(covered: 0, total: 5) == 0)
        #expect(CoverageRollup.Share.percent(covered: 7, total: 7) == 100)
        #expect(CoverageRollup.Share.percent(covered: 0, total: 0) == nil)
    }

    @Test("""
        coverage numbers come from the coverage collector, percentages and linked public functions are better higher, \
        unmapped entries and unlinked public functions lower, the rest neutral, and a missing one is never 0
        """)
    func metrics() throws {
        let report = try CoverageFixture.report()
        let production = try #require(report.rollups.first { $0.scope == .project && $0.name == "production" })
        let numbers = try RollupMetrics.metrics(of: production).filter { $0.path.hasPrefix("coverage.") }
        #expect(numbers.isEmpty == false)
        #expect(numbers.allSatisfy { $0.collector == CoverageAdapter.name })
        #expect(numbers.contains { $0.path == "coverage.lines.percent" && $0.value == 79.31 })
        #expect(numbers.contains { $0.path == "coverage.publicFunctions.linkedTests.p90" && $0.value == 1 })
        #expect(numbers.contains { $0.path == "coverage.attached.regions.total" && $0.value == 12 })
        let unlinked = try #require(report.rollups.first { $0.name == "Unlinked" })
        let unmeasured = try RollupMetrics.metrics(of: unlinked).map(\.path)
        #expect(unmeasured.contains { $0.hasPrefix("coverage.lines.") || $0.hasPrefix("coverage.regions.") } == false)
        #expect(unmeasured.contains("coverage.functions.noData"))

        let directions: [String: MetricDirection] = [
            "coverage.lines.percent": .higherIsBetter,
            "coverage.regions.percent": .higherIsBetter,
            "coverage.publicFunctions.linked": .higherIsBetter,
            "coverage.unmapped": .lowerIsBetter,
            "coverage.publicFunctions.unlinked": .lowerIsBetter,
            "coverage.lines.covered": .neutral,
            "coverage.lines.total": .neutral,
            "coverage.functions.executed": .neutral,
            "coverage.publicFunctions.reachedGenerically": .neutral,
            "coverage.publicFunctions.linkedTests.median": .neutral,
            "coverage.attached.lines.percent": .neutral
        ]
        for (path, direction) in directions {
            #expect(MetricDirection.of(path) == direction, "\(path)")
            #expect(CountedMetrics.value(nil, metric: path) == nil, "\(path)")
        }
    }
}

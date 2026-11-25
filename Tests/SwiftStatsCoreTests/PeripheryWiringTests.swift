import Foundation
@testable import SwiftStatsCore
import Testing

/// What the `periphery` collector takes from the scan and the `index`
/// collector's run (M7, design §2.3, §5.3): both runs' entries classed
/// against the scan's files and records and, when the index ran, the
/// USRs it read as local, as the T1 group hands them on; and the
/// quarantine folder left as the index made it when the index failed
/// after moving units; a failing run's reason taken from the standard
/// output kept in the build directory when its standard error says
/// nothing else. A copy of the Index fixture is scanned against its
/// recorded build and dump, and a fake outskirts acts out the recorded
/// runs, the production run's unused local moved to a place no record
/// holds, where its place alone would make it production code.
/// Serialized, each scan on a thread of its own, as the index collector's
/// tests are.
@Suite("Periphery collector's wiring", .serialized)
struct PeripheryWiringTests {
    /// The stale case's units the index's quarantine moves.
    private static let staleUnits = ["Formatting.o-2O0IO76AFY1BN", "Relay.o-IUHAYC5KOBIV"]
    /// The roots run's entries, by name and class.
    private static let rootsClasses = [
        "unusedComputed production", "unusedTotal local", "unusedHelper() production", "neverCalled() production",
        "Unused production", "Unused production", "relay() production", "unusedInDependency outsideRoot"
    ]
    /// The production run's entries' files.
    private static let productionFiles = [
        "Sources/IndexCore/Accessors.swift", "Sources/IndexCore/Locals.swift", "Sources/IndexCore/Locals.swift",
        "Sources/IndexCore/TestOnly.swift", "Sources/IndexCore/TestOnly.swift",
        "Sources/IndexCore/Unused+Extra.swift", "Sources/IndexCore/Unused.swift", "Sources/Kits/Relay.swift",
        "Sources/Kits/Support.swift", nil
    ]

    /// The production run's entries, by name and class, `unusedTotal`
    /// classed `local`.
    private static func productionClasses(local: String) -> [String] {
        [
            "unusedComputed production", "unusedTotal \(local)", "unusedHelper() production",
            "onlyTestsCall() production", "neverCalled() production", "Unused production", "Unused production",
            "relay() production", "parseLine(_:) production", "unusedInDependency outsideRoot"
        ]
    }

    /// The recorded runs, the production run's `unusedTotal` placed on
    /// `Locals.swift`'s first line, a doc comment no record holds.
    private static func movedLocal() throws -> FakePeriphery.Scenario {
        var scenario = try FakePeriphery.recorded()
        let production = scenario.outputs[.production] ?? ""
        #expect(production.contains("/Sources/IndexCore/Locals.swift:26:9"))
        scenario.outputs[.production] = production.replacingOccurrences(
            of: "/Sources/IndexCore/Locals.swift:26:9",
            with: "/Sources/IndexCore/Locals.swift:1:1"
        )
        return scenario
    }

    /// Runs the T1 group on the fixture with `scan`, outskirts acted out
    /// by a fake playing the moved-local scenario, and passes the copy
    /// and the group to `check`.
    private static func grouped(
        with scan: IndexFixtureScan,
        check: (BuildFixture, PackageScanner.IndexGroup) throws -> Void
    ) async throws {
        let fake = try FakePeriphery.make(try movedLocal())
        defer { fake.remove() }
        var configured = scan
        configured.extra = fake.configuration + scan.extra
        try await configured.runGroup(check: check)
    }

    /// `entries` by name and class.
    private static func classes(_ entries: [PeripheryEntry]) -> [String] {
        entries.map { "\($0.name) \($0.entryClass.rawValue)" }
    }

    @Test("""
        with the index running, both runs' entries are classed against the scan's files, and the unused local \
        is local by the USR the index read as local, even where its place alone would say production
        """)
    func classedWithIndex() async throws {
        try await Self.grouped(with: try IndexFixtureScan()) { _, group in
            #expect(group.indexStatus.state == .ran)
            #expect(group.readers[1].result.status.state == .ran)
            let output = try #require(group.peripheryOutput)
            #expect(output.version == "3.28.0" && output.retained == ["IndexCore", "index-kit"])
            #expect(Self.classes(output.entries(of: .roots)) == Self.rootsClasses)
            let production = output.entries(of: .production)
            #expect(Self.classes(production) == Self.productionClasses(local: "local"))
            #expect(production.map(\.file) == Self.productionFiles)
            #expect(production[1].line == 1 && production[1].column == 1)
            #expect(output.entries.count == 18)
        }
    }

    @Test("""
        with the index disabled, the entries are classed against the scan's files by place alone: the unused \
        local where a record holds it is local, and where none does is production code
        """)
    func classedWithoutIndex() async throws {
        var scan = try IndexFixtureScan()
        scan.extra = "  index:\n    enabled: false\n"
        try await Self.grouped(with: scan) { _, group in
            #expect(group.indexStatus.state == .skipped)
            #expect(group.readers[1].result.status.reason == PeripheryAdapter.positionNote)
            let output = try #require(group.peripheryOutput)
            #expect(output.retained == ["IndexCore", "index-kit"])
            #expect(Self.classes(output.entries(of: .roots)) == Self.rootsClasses)
            let production = output.entries(of: .production)
            #expect(Self.classes(production) == Self.productionClasses(local: "production"))
            #expect(production.map(\.file) == Self.productionFiles)
        }
    }

    @Test("""
        a run exiting 1 with nothing on standard error but outskirts' routine warning fails the collector \
        with the last lines of the standard output kept in the build directory, paths redacted
        """)
    func reasonFromKeptOutput() async throws {
        var scenario = try FakePeriphery.recorded()
        scenario.outputs[.roots] = "error: explained on standard output at @ROOT@/x\n"
        scenario.statuses[.roots] = 1
        let fake = try FakePeriphery.make(scenario)
        defer { fake.remove() }
        var scan = try IndexFixtureScan()
        scan.extra = fake.configuration
        try await scan.run { _, outcome in
            #expect(outcome.statuses["periphery"]?.state == .failed)
            #expect(outcome.statuses["periphery"]?.reason
                == "outskirts scan (roots) exited 1: error: explained on standard output at <package>/x")
            #expect(fake.calls == ["version", "roots"])
        }
    }

    @Test("""
        when the index fails after moving the stale case's units out of the store, outskirts still runs and \
        the quarantine folder keeps the units the index moved
        """)
    func quarantineAfterFailedIndex() async throws {
        let fake = try FakePeriphery.make(try FakePeriphery.recorded())
        defer { fake.remove() }
        var scan = try IndexFixtureScan()
        scan.dump = "reader-stale.json"
        scan.scenario.describe = try IndexFixtureScan.staleDescribe()
        scan.extra = fake.configuration
        // Only the stale units and those outside the package: none is read,
        // so the index fails once its quarantine has run.
        scan.source = { source in
            RecordedIndexSource(
                units: source.units.values.filter { unit in
                    Self.staleUnits.contains(unit.name) || unit.module == "IndexDepKit"
                        || unit.name.hasPrefix("test_entry_point.")
                },
                records: Array(source.records.values)
            )
        }
        scan.prepare = { fixture in
            let root = fixture.package.root
            try FileManager.default.copyItem(
                at: root.appendingPathComponent(IndexFixture.staleRename.from),
                to: root.appendingPathComponent(IndexFixture.staleRename.to)
            )
            let units = URL(fileURLWithPath: fixture.paths.build).appendingPathComponent("out/v5/units")
            try FileManager.default.createDirectory(at: units, withIntermediateDirectories: true)
            for name in Self.staleUnits + ["Kit.o-3SHEV4SLQQ5MS"] {
                try Data().write(to: units.appendingPathComponent(name))
            }
        }
        try await scan.run { fixture, outcome in
            #expect(outcome.statuses["index"]?.state == .failed)
            #expect(outcome.statuses["index"]?.reason == IndexAdapter.noUnitsReason)
            let periphery = try #require(outcome.statuses["periphery"])
            #expect(periphery.state == .ran)
            #expect(periphery.reason == PeripheryAdapter.positionNote)
            #expect(fake.calls == ["version", "roots", "production"])
            let build = URL(fileURLWithPath: fixture.paths.build)
            let moved = try FileManager.default.contentsOfDirectory(
                atPath: build.appendingPathComponent(UnitFilter.quarantineDirectory).path
            )
            #expect(moved.sorted() == Self.staleUnits)
            let left = try FileManager.default.contentsOfDirectory(
                atPath: build.appendingPathComponent("out/v5/units").path
            )
            #expect(left == ["Kit.o-3SHEV4SLQQ5MS"])
        }
    }
}

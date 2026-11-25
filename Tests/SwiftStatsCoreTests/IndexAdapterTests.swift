import Foundation
@testable import SwiftStatsCore
import Testing

/// The `index` collector's run over the T1 build's store (M7, design §2.3,
/// §2.4): stale and other-module units moved out of the store, and every
/// way the read fails, each failure's reason free of absolute paths and
/// leaving no index block or roll-up counts. A copy of the Index fixture is
/// scanned against its recorded build and dump.
/// Serialized, and each scan runs on a thread of its own: a test holding a
/// pool thread for seconds starves `BlockingAsyncTests`' detached tasks.
@Suite("Index collector", .serialized)
struct IndexAdapterTests {
    /// The stale case's units the quarantine moves: the renamed file's and
    /// the moved file's old ones.
    private static let staleUnits = ["Formatting.o-2O0IO76AFY1BN", "Relay.o-IUHAYC5KOBIV"]

    /// Checks that `outcome`'s index collector failed for `reason` with its
    /// options and the reader's identity, and left no results.
    private static func expectFailed(_ outcome: IndexGroupHarness.Outcome, reason: String) {
        #expect(outcome.statuses["index"] == CollectorStatus(
            name: "index",
            state: .failed,
            version: nil,
            reason: reason,
            options: IndexAdapter.options
        ))
        #expect(outcome.run("index")?.identity == "git:64aa0b26913249c4e7c21d351a215fba02702003")
        #expect(outcome.report.index == nil)
        #expect(outcome.report.rollups.allSatisfy { $0.index == nil })
        #expect(outcome.report.build != nil)
    }

    @Test("""
        on the stale case, the renamed and moved files' old units are listed stale and moved into the emptied \
        quarantine folder, and nothing else is
        """)
    func quarantine() async throws {
        var scan = try IndexFixtureScan()
        scan.dump = "reader-stale.json"
        scan.scenario.describe = try IndexFixtureScan.staleDescribe()
        scan.prepare = { fixture in
            let root = fixture.package.root
            try FileManager.default.copyItem(
                at: root.appendingPathComponent(IndexFixture.staleRename.from),
                to: root.appendingPathComponent(IndexFixture.staleRename.to)
            )
            let build = URL(fileURLWithPath: fixture.paths.build)
            let units = build.appendingPathComponent("out/v5/units")
            try FileManager.default.createDirectory(at: units, withIntermediateDirectories: true)
            for name in Self.staleUnits + ["Kit.o-3SHEV4SLQQ5MS"] {
                try Data().write(to: units.appendingPathComponent(name))
            }
            let quarantine = build.appendingPathComponent(UnitFilter.quarantineDirectory)
            try FileManager.default.createDirectory(at: quarantine, withIntermediateDirectories: true)
            try Data().write(to: quarantine.appendingPathComponent("Leftover.o-OLD"))
        }
        try await scan.run { fixture, outcome in
            let index = try #require(outcome.report.index)
            #expect(outcome.statuses["index"]?.state == .ran)
            #expect(index.store.counts.stale == 2 && index.store.counts.quarantined == 2)
            let stale = index.store.units.filter { $0.unitClass == .stale }
            #expect(stale.map(\.name) == Self.staleUnits)
            #expect(stale.map(\.target) == ["IndexCore", "index-kit"])
            let build = URL(fileURLWithPath: fixture.paths.build)
            let moved = try FileManager.default.contentsOfDirectory(
                atPath: build.appendingPathComponent(UnitFilter.quarantineDirectory).path
            )
            #expect(moved.sorted() == Self.staleUnits)
            let units = build.appendingPathComponent("out/v5/units")
            let left = try FileManager.default.contentsOfDirectory(atPath: units.path)
            #expect(left == ["Kit.o-3SHEV4SLQQ5MS"])
            let relay = try #require(index.records.first { $0.key == "index-kit::func relay() -> Int" })
            #expect(relay.usr == "s:13index_support5relaySiyF")
        }
    }

    @Test("a toolchain without libIndexStore.dylib fails the collector, naming its folder by placeholder")
    func noLibrary() async throws {
        var scan = try IndexFixtureScan()
        scan.hasLibrary = false
        try await scan.run { _, outcome in
            Self.expectFailed(outcome, reason: "the toolchain has no libIndexStore.dylib (<toolchain>/usr/lib)")
        }
    }

    @Test("a store that doesn't open fails the collector with its error, the build directory written <build>")
    func storeDoesNotOpen() async throws {
        var scan = try IndexFixtureScan()
        scan.source = { source in
            let bom = source.units.values.first { $0.name.hasPrefix("Bom.o-") }?.mainFile ?? ""
            let root = URL(fileURLWithPath: bom)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let store = root.appendingPathComponent(".swiftstats/index-build/out")
            throw IndexStoreReader.Failure(description: "the index store at \(store.path) doesn't read: broken")
        }
        try await scan.run { _, outcome in
            Self.expectFailed(outcome, reason: "the index store at <build>/out doesn't read: broken")
        }
    }

    @Test("a unit that doesn't read fails the collector, naming it, with no partial results")
    func unitDoesNotRead() async throws {
        var scan = try IndexFixtureScan()
        scan.source = { CountingIndexSource($0, failing: ["Ring.o-2RAFKBSY9VGN2"]) }
        try await scan.run { _, outcome in
            Self.expectFailed(outcome, reason: "unit Ring.o-2RAFKBSY9VGN2 doesn't read: refused Ring.o-2RAFKBSY9VGN2")
        }
    }

    @Test("a store holding none of the package's units fails the collector while the scan has records")
    func noPackageUnits() async throws {
        var scan = try IndexFixtureScan()
        scan.source = { source in
            RecordedIndexSource(
                units: source.units.values.filter { unit in
                    unit.module == "IndexDepKit" || unit.name.hasPrefix("test_entry_point.")
                },
                records: Array(source.records.values)
            )
        }
        try await scan.run { _, outcome in
            Self.expectFailed(outcome, reason: IndexAdapter.noUnitsReason)
        }
    }

    @Test("""
        the index block survives attaching the history, and attaching no index takes the roll-ups' USR counts \
        away; the block reads back as written
        """)
    func attachAndRoundTrip() async throws {
        try await IndexFixtureScan().run { _, outcome in
            let index = try #require(outcome.report.index)
            let history = outcome.report.with(history: nil, status: HistoryCollector.notRequested)
            #expect(history.index == index)
            #expect(history.rollups == outcome.report.rollups)
            let status = try #require(outcome.statuses["index"])
            let cleared = outcome.report.with(index: nil, status: status)
            #expect(cleared.index == nil && cleared.rollups.allSatisfy { $0.index == nil })
            #expect(cleared.with(index: index, status: status) == outcome.report)

            let data = try JSONEncoder().encode(index)
            #expect(try JSONDecoder().decode(IndexReport.self, from: data) == index)
            let text = String(bytes: data, encoding: .utf8) ?? ""
            #expect(text.contains("\"reason\":\"inactiveIfBranch\""))
            #expect(text.contains("\"class\":\"kept\""))
            #expect(text.contains("\"subreason\":\"requirement\""))
            let unknown = Data(text.replacingOccurrences(of: "\"class\":\"kept\"", with: "\"class\":\"gone\"").utf8)
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(IndexReport.self, from: unknown) }
        }
    }
}

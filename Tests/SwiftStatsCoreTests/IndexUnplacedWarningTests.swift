import Foundation
@testable import SwiftStatsCore
import Testing

/// The index collector's warning naming the package type definitions no
/// type record holds (M7, design §4.3, review C12), end to end: a scan of
/// the Index fixture whose recorded index defines a struct the scan has no
/// type record for reports it, and a plain rescan keeping the T1 results
/// keeps it. `TypeNestingTests` covers the warning's text. Serialized: the
/// fixture scans run on threads of their own, as the index collector's
/// tests do.
@Suite("Index unplaced-type warning", .serialized)
struct IndexUnplacedWarningTests {
    /// The fixture file the unplaced definition is put in.
    private static let file = "Sources/IndexCore/Ring.swift"
    /// The line of `file` it is put on, in the top-level closure of
    /// `defaultWidths`, where no type record holds it.
    private static let line = 32
    /// Its USR and name.
    private static let usr = "s:9IndexCore4DemoV"

    /// The explicit definition of the struct `usr` on `line`.
    private static let definition = IndexOccurrenceFact(
        line: line,
        column: 37,
        roles: IndexSymbolKind.Role.definition,
        usr: usr,
        name: usr,
        kind: IndexSymbolKind.struct,
        subkind: IndexSymbolKind.Subkind.plain,
        properties: 0,
        relations: []
    )

    /// The warnings of `report` led by the index collector's name.
    private static func indexWarnings(_ report: ScanReport) -> [ScanWarning] {
        report.warnings.filter { $0.file == nil && $0.message.hasPrefix(IndexAdapter.name + ": ") }
    }

    /// A workspace on `fixture` storing in `made`.
    private static func workspace(_ fixture: BuildFixture, store made: TemporaryStore) throws -> SnapshotWorkspace {
        try SnapshotWorkspace(
            packageRoot: fixture.package.root,
            configurationFile: nil,
            storeOverride: made.url.path,
            build: SnapshotHarness.build,
            describer: fixture.package.describer,
            tools: SnapshotHarness.noTools
        )
    }

    /// `fixture` scanned again without the T1 group, as the test build at
    /// `c1`, with its `.swiftstats.yml`.
    private static func plainRescan(_ fixture: BuildFixture) throws -> ScannedSnapshot {
        let root = fixture.package.root
        return try SnapshotScanner(
            scanner: PackageScanner(describer: fixture.package.describer, tools: SnapshotHarness.noTools),
            build: SnapshotHarness.build
        )
        .scan(
            packageAt: root,
            configurationFile: StoreLocation.localConfiguration(packageRoot: root),
            git: SnapshotHarness.git(commit: "c1"),
            toolchain: SnapshotHarness.toolchain,
            date: IndexCarrySamples.later(1),
            history: .skipped("test"),
            tiers: .syntaxOnly
        )
    }

    @Test("""
        a scan whose index defines a type no type record holds warns once, naming it with its place, and a plain \
        rescan that keeps the T1 results keeps the warning
        """)
    func scanAndCarry() async throws {
        let fake = try FakePeriphery.make(try FakePeriphery.recorded())
        defer { fake.remove() }
        var scan = try IndexFixtureScan()
        scan.extra = fake.configuration
        scan.source = { source in
            source.changingOccurrences(inFile: "Ring.swift", adding: [Self.definition]) { $0 }
        }
        try await scan.run { fixture, outcome in
            let expected = ScanWarning(
                file: nil,
                message: "index: 1 package type definitions found no type record of their kind (a type the scan "
                    + "doesn't measure, such as one inside a macro's closure), so they have no type row, fan-in or "
                    + "cycle: \(Self.usr) (\(Self.file):\(Self.line))"
            )
            #expect(outcome.statuses["index"]?.state == .ran)
            #expect(Self.indexWarnings(outcome.report) == [expected])
            #expect(outcome.report.index?.types.contains { $0.usr == Self.usr } == false)

            let made = try TemporaryStore("IndexUnplacedWarning")
            defer { made.remove() }
            let workspace = try Self.workspace(fixture, store: made)
            _ = try workspace.save(outcome.snapshot, drop: [])
            let rescan = try Self.plainRescan(fixture)

            let carried = try workspace.save(rescan, drop: []).snapshot

            #expect(Self.indexWarnings(rescan.report).isEmpty)
            #expect(carried.report.index == outcome.report.index)
            #expect(Self.indexWarnings(carried.report) == [expected])
        }
    }
}

import Foundation
@testable import SwiftStatsCore
import Testing

/// The USR join on the Index fixture's recorded index (M7, design §3): a
/// copy scanned with `--index` against its recorded build, the `index`
/// collector reading `reader.json`. Every record's USR, secondary accessor
/// USR and reason is pinned in `Tests/Fixtures/IndexUSRs.golden.txt`,
/// first written from the independent checker's own join
/// (`index-check.py usr --dump`) and read by hand; the accessor kinds, the
/// subscripts, the lists and the counts are hand-written here too.
/// Serialized, and each scan runs on a thread of its own: a test holding a
/// pool thread for seconds starves `BlockingAsyncTests`' detached tasks.
@Suite("USR join", .serialized)
struct USRJoinTests {
    /// The golden table of every record's USRs.
    private static let golden = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent("IndexUSRs.golden.txt")

    /// Each accessor record of the fixture with the USR its accessor kind
    /// alone matches: the subkinds `get`, `set`, `willSet`, `didSet`,
    /// `_read`, `_modify`, `unsafeAddress`, `unsafeMutableAddress` and the
    /// `init` accessor's raw 1016.
    private static let accessors = [
        "IndexCore::Storage::var head: Int { get }": "s:9IndexCore7StorageV4headSivg",
        "IndexCore::Storage::var head: Int { set }": "s:9IndexCore7StorageV4headSivs",
        "IndexCore::Storage::var observed { willSet }": "s:9IndexCore7StorageV8observedSivw",
        "IndexCore::Storage::var observed { didSet }": "s:9IndexCore7StorageV8observedSivW",
        "IndexCore::Storage::var coroutine: Int { _read }": "s:9IndexCore7StorageV9coroutineSivr",
        "IndexCore::Storage::var coroutine: Int { _modify }": "s:9IndexCore7StorageV9coroutineSivM",
        "IndexCore::Addressed::var value: Int { unsafeAddress }": "s:9IndexCore9AddressedV5valueSivlu",
        "IndexCore::Addressed::var value: Int { unsafeMutableAddress }": "s:9IndexCore9AddressedV5valueSivau",
        "IndexCore::Initialized::var value: Int { init }": "s:9IndexCore11InitializedV5valueSivi"
    ]

    /// `index`'s records as the golden table writes them: key, USR,
    /// secondary accessor USR and reason, `-` for none, tab-separated.
    private static func table(_ index: IndexReport) -> String {
        index.records.map { record in
            [record.key, record.usr ?? "-", record.usrAccessor ?? "-", record.reason?.rawValue ?? "-"]
                .joined(separator: "\t")
        }
        .joined(separator: "\n") + "\n"
    }

    /// A definition occurrence of `kind` and `subkind` at 1:1.
    private static func definition(kind: Int, subkind: Int) -> IndexOccurrenceFact {
        IndexOccurrenceFact(
            line: 1,
            column: 1,
            roles: IndexSymbolKind.Role.definition,
            usr: "s:test",
            name: "test",
            kind: kind,
            subkind: subkind,
            properties: 0,
            relations: []
        )
    }

    /// The listing of a requirement of `Protocols.swift` without a body: an
    /// instance method `name` with `usr`, at column 10 of `line`.
    private static func requirement(_ usr: String, name: String, line: Int) -> USRListing {
        USRListing(
            kind: .noRecord,
            subreason: .requirement,
            usr: usr,
            key: nil,
            symbolKind: IndexSymbolKind.instanceMethod,
            name: name,
            file: "Sources/IndexCore/Protocols.swift",
            line: line,
            column: 10
        )
    }

    /// To accept a deliberate change, run with `SWIFTSTATS_UPDATE_GOLDEN=1`
    /// and review the diff of `Tests/Fixtures/IndexUSRs.golden.txt`.
    @Test("""
        every record of the recorded fixture gets the USR, secondary accessor USR and reason of the golden \
        table, listed in the scan's record order
        """)
    func goldenTable() async throws {
        try await IndexFixtureScan().run { _, outcome in
            let index = try #require(outcome.report.index)
            let actual = Self.table(index)
            if ProcessInfo.processInfo.environment["SWIFTSTATS_UPDATE_GOLDEN"] == "1" {
                try actual.write(to: Self.golden, atomically: true, encoding: .utf8)
            }
            let expected = try String(contentsOf: Self.golden, encoding: .utf8)
            #expect(
                actual == expected,
                "USRs differ from IndexUSRs.golden.txt; to accept, set SWIFTSTATS_UPDATE_GOLDEN=1"
            )
            #expect(index.records.map(\.key) == outcome.report.records.map(\.key))
            #expect(index.records.count { $0.usr != nil } == 100)
        }
    }

    @Test("each accessor record gets the definition whose accessor subkind matches its accessor kind")
    func accessorKinds() async throws {
        try await IndexFixtureScan().run { _, outcome in
            let index = try #require(outcome.report.index)
            let usrs = Dictionary(uniqueKeysWithValues: index.records.map { ($0.key, $0.usr) })
            for (key, usr) in Self.accessors {
                #expect(usrs[key] == usr, "\(key)")
            }
        }
    }

    @Test("an accessor record is compatible with a function or method of its own accessor subkind alone")
    func accessorSubkinds() throws {
        let fixture = try BuildFixture()
        defer { fixture.remove() }
        let subkinds = [
            "get": 3, "set": 4, "willSet": 1_000, "didSet": 1_001, "unsafeAddress": 1_002,
            "unsafeMutableAddress": 1_003, "_read": 1_014, "_modify": 1_015, "init": 1_016
        ]
        for (keyword, own) in subkinds {
            let record = try #require(
                fixture.measured.records.first { $0.kind == .accessor && $0.accessorKind == keyword },
                "\(keyword)"
            )
            for (other, subkind) in subkinds {
                for kind in [IndexSymbolKind.instanceMethod, IndexSymbolKind.function] {
                    let occurrence = Self.definition(kind: kind, subkind: subkind)
                    #expect(USRKinds.isCompatible(record, with: occurrence) == (subkind == own), "\(keyword) \(other)")
                }
            }
            let property = Self.definition(kind: IndexSymbolKind.instanceProperty, subkind: own)
            #expect(USRKinds.isCompatible(record, with: property) == false)
        }
    }

    @Test("""
        a shorthand subscript gets its getter as its secondary accessor USR, and a subscript with explicit get \
        and set gets none, its accessors taking theirs
        """)
    func subscripts() async throws {
        try await IndexFixtureScan().run { _, outcome in
            let index = try #require(outcome.report.index)
            let records = Dictionary(uniqueKeysWithValues: index.records.map { ($0.key, $0) })
            let storage = try #require(records["IndexCore::Storage::subscript(_: Int) -> Int"])
            #expect(storage.usr == "s:9IndexCore7StorageVyS2icip")
            #expect(storage.usrAccessor == "s:9IndexCore7StorageVyS2icig")
            let ring = try #require(records["IndexCore::Ring::subscript(_: Int) -> Int"])
            #expect(ring.usrAccessor == "s:9IndexCore4RingVyS2icig")
            let slot = try #require(records["IndexCore::Storage::subscript(slot: Int) -> Int"])
            #expect(slot.usr == "s:9IndexCore7StorageV4slotS2i_tcip")
            #expect(slot.usrAccessor == nil)
            #expect(records["IndexCore::Storage::subscript(slot: Int) -> Int / { get }"]?.usr
                == "s:9IndexCore7StorageV4slotS2i_tcig")
            #expect(records["IndexCore::Storage::subscript(slot: Int) -> Int / { set }"]?.usr
                == "s:9IndexCore7StorageV4slotS2i_tcis")
            #expect(index.records.count { $0.usrAccessor != nil } == 3)
        }
    }

    @Test("""
        implicit definitions such as Swift Testing's peers are skipped, the body-less requirements are listed \
        apart, the collision is told apart by its USRs, and the XCTest method's USR is counted as Objective-C
        """)
    func listsAndCounts() async throws {
        try await IndexFixtureScan().run { _, outcome in
            let index = try #require(outcome.report.index)
            #expect(index.definitions == IndexDefinitions(joined: 103, implicit: 121, secondary: 3, objc: 1))
            #expect(index.disagreements.isEmpty)
            let tests = index.records.filter { $0.key.hasPrefix("IndexCoreTests::") }
            #expect(tests.count == 6 && tests.allSatisfy { $0.usr?.hasPrefix("s:14IndexCoreTests") == true })
            #expect(index.withoutRecord == [
                Self.requirement("s:9IndexCore5ShapeP4areaSiyF", name: "area()", line: 4),
                Self.requirement("s:9IndexCore7GreeterP5greetSSyF", name: "greet()", line: 21)
            ] + USRRequirementTests.labeledRequirements)
            let collided = "IndexCore::func measure(_: Data) -> Int @ Sources/IndexCore/"
            #expect(index.collisions.map(\.kind) == [.collision, .collision])
            #expect(index.collisions.map { $0.key ?? "" } == [collided + "Bytes.swift", collided + "Dependency.swift"])
            #expect(index.collisions.map { $0.usr ?? "" } == [
                "s:9IndexCore7measureySi10Foundation4DataVF", "s:9IndexCore7measureySi0A6DepKit4DataVF"
            ])
            let xctest = try #require(index.records.first { $0.key.hasPrefix("IndexXCTests::") })
            #expect(xctest.usr == "c:@M@IndexXCTests@objc(cs)LayoutXCTests(im)testLayout")
        }
    }

    @Test("""
        the index collector ran with the reader's version, options and pin, listing the store's units by \
        class, the library-product targets it read and every scanned file hashed after the build
        """)
    func collectorAndStore() async throws {
        try await IndexFixtureScan().run { fixture, outcome in
            #expect(outcome.statuses["index"] == CollectorStatus(
                name: "index",
                state: .ran,
                version: "indexstore-db swift-6.4.2-RELEASE",
                reason: nil,
                options: IndexAdapter.options
            ))
            #expect(IndexAdapter.options.first == "reader: indexstore-db IndexStore 64aa0b2")
            #expect(IndexAdapter.options.dropFirst().first == "libIndexStore: toolchain")
            #expect(outcome.run("index")?.identity == "git:64aa0b26913249c4e7c21d351a215fba02702003")
            let index = try #require(outcome.report.index)
            #expect(index.store.layout == "swiftbuild")
            #expect(index.store.counts == IndexUnitCounts(
                Array(repeating: .kept, count: 22) + Array(repeating: .otherPackage, count: 4),
                quarantined: 0
            ))
            #expect(index.store.records == 22)
            #expect(index.store.units.count == 22 && index.store.units.allSatisfy { $0.unitClass == .kept })
            #expect(index.store.units.first { $0.name == "Support.o-DGRO9MV486NA" } == IndexUnitRow(
                name: "Support.o-DGRO9MV486NA",
                target: "index-support",
                mainFile: "Sources/Kits/Support.swift",
                triple: "arm64-apple-macos14.0",
                unitClass: .kept
            ))
            #expect(index.libraryModules == ["IndexCore", "index-kit"])
            #expect(index.files.map(\.path) == fixture.measured.files.map(\.path).sorted())
            let hashes = Dictionary(uniqueKeysWithValues: fixture.measured.files.map { ($0.path, $0.sha256) })
            #expect(index.files.allSatisfy { $0.sha256 == hashes[$0.path] })
        }
    }

    @Test("""
        every roll-up scope counts its records with a USR, without one by reason and in a disagreement, as \
        the index collector's metrics
        """)
    func rollups() async throws {
        try await IndexFixtureScan().run { _, outcome in
            let rollups = outcome.report.rollups
            #expect(rollups.allSatisfy { $0.index != nil })
            let core = try #require(rollups.first { $0.scope == .module && $0.name == "IndexCore" }?.index)
            #expect(core.withUSR == 86)
            #expect(core.withoutUSR["inactiveIfBranch"] == 2)
            #expect(core.withoutUSR.count == USRReason.allCases.count)
            #expect(core.withoutUSR.values.reduce(0, +) == 2)
            let app = try #require(rollups.first { $0.scope == .module && $0.name == "IndexApp" }?.index)
            #expect(app.withUSR == 0 && app.withoutUSR["topLevelCode"] == 1)
            let production = try #require(rollups.first { $0.scope == .project && $0.name == "production" }?.index)
            let tests = try #require(rollups.first { $0.scope == .project && $0.name == "tests" }?.index)
            #expect(production.withUSR + tests.withUSR == 100)
            #expect(tests.withUSR == 7 && tests.disagreements == 0)
            let metrics = try rollups.flatMap(RollupMetrics.metrics(of:)).filter { $0.path.hasPrefix("index.") }
            #expect(metrics.isEmpty == false && metrics.allSatisfy { $0.collector == "index" })
            #expect(metrics.contains { $0.path == "index.withoutUSR.inactiveIfBranch" && $0.value == 2 })
        }
    }
}

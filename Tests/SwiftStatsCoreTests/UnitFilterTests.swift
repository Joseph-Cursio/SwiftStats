//
//  UnitFilterTests.swift
//  SwiftStatsCoreTests
//
//  `UnitFilter` (M7, design §2.3): each unit's class on the Index
//  fixture's recorded dumps and on units injected beside them, in the
//  order the classes apply, and the quarantine of stale and other-module
//  units.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// The stale-unit filter and the quarantine.
@Suite("Unit filter")
struct UnitFilterTests {
    /// The units every recording classes as another package's: IndexDep's
    /// and Swift Build's generated test entry points.
    private static let otherPackage = [
        "DepKit.o-3QG4QQUHJ0YQ0", "Payload.o-5SC9XY250QI0", "test_entry_point.o-27JSI56QYPVCU",
        "test_entry_point.o-PZ6IP14EL0BK"
    ]
    /// The stale case's stale units: the renamed file's, and the moved
    /// file's unit for the target it left.
    private static let stale = ["Formatting.o-2O0IO76AFY1BN", "Relay.o-IUHAYC5KOBIV"]
    /// A kept unit the injected units copy.
    private static let ringName = "Ring.o-2RAFKBSY9VGN2"

    /// Each unit's class, by name.
    private static func classes(_ classed: [UnitFilter.ClassedUnit]) -> [String: UnitFilter.UnitClass] {
        Dictionary(uniqueKeysWithValues: classed.map { ($0.unit.name, $0.unitClass) })
    }

    /// The names of the files in `directory`, sorted.
    private static func names(in directory: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory).sorted()
    }

    @Test("on the stale recording, the renamed and moved files' old units are stale, the rest kept or other packages'")
    func staleRecording() throws {
        let harness = try IndexWalkHarness.stale()
        let classes = Self.classes(try harness.filter.classify(harness.units))
        let expected = harness.units.map(\.name).reduce(into: [String: UnitFilter.UnitClass]()) { result, name in
            result[name] = Self.stale.contains(name) ? .stale : Self.otherPackage.contains(name) ? .otherPackage : .kept
        }

        #expect(classes == expected)
        #expect(classes["Relay.o-3SE1FXZN573EB"] == .kept)
        #expect(classes["LineFormatting.o-G6KAE1AVKNE3"] == .kept)
        #expect(classes.values.count { $0 == .kept } == 22)
    }

    @Test("on the first build's recording every package unit is kept")
    func freshRecording() throws {
        let harness = try IndexWalkHarness.fresh()
        let classes = Self.classes(try harness.filter.classify(harness.units))

        #expect(classes.count == 26)
        #expect(Set(classes.filter { $0.value == .otherPackage }.keys) == Set(Self.otherPackage))
        #expect(classes.values.count { $0 == .kept } == 22)
    }

    @Test("a package file's unit for a module no target has is another module's, before it can be stale")
    func otherModule() throws {
        let harness = try IndexWalkHarness.stale()
        let ring = try harness.unit(Self.ringName)
        let renamed = try harness.unit("Formatting.o-2O0IO76AFY1BN")
        let units = harness.units + [
            ring.named("Ring.o-GONE").inModule("GoneModule"),
            renamed.named("Formatting.o-GONE").inModule("GoneModule")
        ]
        let classes = Self.classes(try harness.filter.classify(units))

        #expect(classes["Ring.o-GONE"] == .otherModule)
        #expect(classes["Formatting.o-GONE"] == .otherModule)
        #expect(classes[Self.ringName] == .kept)
    }

    @Test("a unit whose file is a source of another target than its module's is stale")
    func movedFile() throws {
        let harness = try IndexWalkHarness.fresh()
        let ring = try harness.unit(Self.ringName)
        let units = harness.units + [ring.named("Ring.o-KIT").inModule("index_kit")]
        let classes = Self.classes(try harness.filter.classify(units))

        #expect(classes["Ring.o-KIT"] == .stale)
        #expect(classes[Self.ringName] == .kept)
    }

    @Test("an older unit of one module, file and triple is a duplicate")
    func duplicate() throws {
        let harness = try IndexWalkHarness.stale()
        let ring = try harness.unit(Self.ringName)
        let older = IndexUnitFact.ModificationDate(
            seconds: ring.modified.seconds,
            nanoseconds: ring.modified.nanoseconds - 1
        )
        let newer = IndexUnitFact.ModificationDate(seconds: ring.modified.seconds + 1, nanoseconds: 0)
        let olderClasses = Self.classes(try harness.filter.classify(
            harness.units + [ring.named("Ring.o-ZZZOLDER").modifiedAt(older)]
        ))
        let newerClasses = Self.classes(try harness.filter.classify(
            harness.units + [ring.named("Ring.o-000NEWER").modifiedAt(newer)]
        ))

        #expect(olderClasses["Ring.o-ZZZOLDER"] == .duplicate)
        #expect(olderClasses[Self.ringName] == .kept)
        #expect(newerClasses["Ring.o-000NEWER"] == .kept)
        #expect(newerClasses[Self.ringName] == .duplicate)
    }

    @Test("a modification-date tie between units of one module, file and triple is broken by the larger unit name")
    func dateTie() throws {
        let harness = try IndexWalkHarness.stale()
        let ring = try harness.unit(Self.ringName)
        let larger = Self.classes(try harness.filter.classify(
            harness.units + [ring.named("Ring.o-ZZZ")]
        ))
        let smaller = Self.classes(try harness.filter.classify(
            harness.units + [ring.named("Ring.o-000")]
        ))

        #expect(larger["Ring.o-ZZZ"] == .kept)
        #expect(larger[Self.ringName] == .duplicate)
        #expect(smaller["Ring.o-000"] == .duplicate)
        #expect(smaller[Self.ringName] == .kept)
    }

    @Test("a unit of another triple makes both units variants, after duplicates are taken out per triple")
    func variant() throws {
        let harness = try IndexWalkHarness.stale()
        let ring = try harness.unit(Self.ringName)
        let host = "arm64-apple-macos26.0"
        let older = IndexUnitFact.ModificationDate(seconds: 1, nanoseconds: 0)
        let units = harness.units + [
            ring.named("Ring.o-HOST").forTriple(host),
            ring.named("Ring.o-HOSTOLD").forTriple(host).modifiedAt(older)
        ]
        let classes = Self.classes(try harness.filter.classify(units))

        #expect(classes["Ring.o-HOST"] == .variant)
        #expect(classes[Self.ringName] == .variant)
        #expect(classes["Ring.o-HOSTOLD"] == .duplicate)
        #expect(classes["Types.o-3KJN8I9ZZRTUI"] == .kept)
    }

    @Test("a system unit, a unit with no main file and units under .build or .swiftstats are classed first")
    func headerClasses() throws {
        let harness = try IndexWalkHarness.fresh()
        let ring = try harness.unit(Self.ringName)
        let system = IndexUnitFact(
            name: "Swift.swiftinterface-SYS",
            module: "IndexCore",
            mainFile: ring.mainFile,
            target: ring.target,
            isSystem: true,
            modified: ring.modified,
            records: [],
            moduleDependencies: []
        )
        let units = harness.units + [
            system,
            ring.named("Empty.o-1").atFile(""),
            ring.named("Built.o-1").atFile(harness.root + "/.build/checkouts/Ring.swift"),
            ring.named("Own.o-1").atFile(harness.root + "/.swiftstats/Ring.swift"),
            ring.named("Outside.o-1").atFile(harness.root + "-other/Sources/IndexCore/Ring.swift"),
            ring.named("Root.o-1").atFile(harness.root)
        ]
        let classes = Self.classes(try harness.filter.classify(units))

        #expect(classes["Swift.swiftinterface-SYS"] == .system)
        #expect(classes["Empty.o-1"] == .otherPackage)
        #expect(classes["Built.o-1"] == .otherPackage)
        #expect(classes["Own.o-1"] == .otherPackage)
        #expect(classes["Outside.o-1"] == .otherPackage)
        #expect(classes["Root.o-1"] == .otherPackage)
        #expect(classes[Self.ringName] == .kept)
    }

    @Test("main files and the describe's sources are compared in NFC")
    func normalization() throws {
        let decomposed = "Cafe\u{301}.swift"
        let composed = "Caf\u{E9}.swift"
        let package = DescribedPackage(name: "Probe", targets: [
            DescribedTarget(
                name: "Lib",
                type: "library",
                moduleType: "SwiftTarget",
                path: "Sources/Lib",
                sources: [decomposed]
            )
        ])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("UnitFilterTests-\(UUID().uuidString)")
        let file = root.appendingPathComponent("Sources/Lib").appendingPathComponent(composed)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: file)
        let realRoot = WorkCopyHarness.realPath(root)
        let filter = try UnitFilter(root: realRoot, scratch: realRoot + "/.swiftstats/index-build", package: package)
        let unit = IndexUnitFact(
            name: "Cafe.o-1",
            module: "Lib",
            mainFile: realRoot + "/Sources/Lib/" + composed,
            target: "arm64-apple-macos14.0",
            isSystem: false,
            modified: IndexUnitFact.ModificationDate(seconds: 1, nanoseconds: 0),
            records: [],
            moduleDependencies: []
        )

        #expect(filter.classify([unit]).map(\.unitClass) == [.kept])
        #expect(filter.packagePath(of: unit.mainFile, module: unit.module) == "Sources/Lib/" + composed)
    }

    @Test("two targets sharing a C99 name can't be filtered")
    func moduleClash() {
        let package = DescribedPackage(name: "Probe", targets: [
            DescribedTarget(name: "my-lib", type: "library", moduleType: "SwiftTarget", path: "Sources/A", sources: []),
            DescribedTarget(name: "my_lib", type: "library", moduleType: "SwiftTarget", path: "Sources/B", sources: [])
        ])

        #expect(throws: (any Error).self) {
            try UnitFilter(root: "/probe", scratch: "/probe/.swiftstats/index-build", package: package)
        }
    }

    @Test("the quarantine moves exactly the stale and other-module units into its emptied folder")
    func quarantine() throws {
        let harness = try IndexWalkHarness.stale()
        let ring = try harness.unit(Self.ringName)
        let units = harness.units + [ring.named("Ring.o-GONE").inModule("GoneModule")]
        let store = harness.build + "/out/v5/units"
        let quarantined = harness.build + "/" + UnitFilter.quarantineDirectory
        try FileManager.default.createDirectory(atPath: store, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: quarantined, withIntermediateDirectories: true)
        for unit in units {
            try Data().write(to: URL(fileURLWithPath: store + "/" + unit.name))
        }
        try Data().write(to: URL(fileURLWithPath: quarantined + "/Leftover.o-1"))
        let filter = try harness.filter

        let moved = try filter.quarantine(filter.classify(units))

        let expected = (Self.stale + ["Ring.o-GONE"]).sorted()
        #expect(moved == expected)
        #expect(try Self.names(in: quarantined) == expected)
        #expect(try Self.names(in: store) == units.map(\.name).filter { expected.contains($0) == false }.sorted())
    }

    @Test("a quarantine with nothing to move leaves its folder empty")
    func quarantineNothing() throws {
        let harness = try IndexWalkHarness.fresh()
        let quarantined = harness.build + "/" + UnitFilter.quarantineDirectory
        try FileManager.default.createDirectory(atPath: quarantined, withIntermediateDirectories: true)
        try Data().write(to: URL(fileURLWithPath: quarantined + "/Leftover.o-1"))
        let filter = try harness.filter

        let moved = try filter.quarantine(filter.classify(harness.units))

        #expect(moved.isEmpty)
        #expect(try Self.names(in: quarantined).isEmpty)
    }

    @Test("a quarantine whose unit file is missing fails with the collector's wording")
    func quarantineFailure() throws {
        let harness = try IndexWalkHarness.stale()
        let filter = try harness.filter
        let classed = filter.classify(harness.units)

        #expect {
            _ = try filter.quarantine(classed)
        } throws: { error in
            String(describing: error).hasPrefix("units couldn't be moved out of the store: ")
        }
    }
}

//
//  IndexWalkTests.swift
//  SwiftStatsCoreTests
//
//  `IndexWalk` and `IndexSnapshot` (M7, design §2.2) over the Index
//  fixture's recorded dumps: which records are read and how often, module
//  names translated to target names, paths in the package, and failures
//  naming what didn't read.
//

@testable import SwiftStatsCore
import Testing

/// Walking an index store through the recorded source.
@Suite("Index walk")
struct IndexWalkTests {
    /// The kept unit the injected variant copies.
    private static let ringName = "Ring.o-2RAFKBSY9VGN2"

    @Test("the walk reads every unit once and each kept or variant unit's records once, and no other unit's")
    func readsOnce() throws {
        let harness = try IndexWalkHarness.stale()
        let ring = try harness.unit(Self.ringName)
        let source = harness.adding([ring.named("Ring.o-HOST").forTriple("arm64-apple-macos26.0")])
        let counting = CountingIndexSource(source, failing: [])

        let snapshot = try IndexWalk.walk(counting, filter: harness.filter)

        let read = Set(snapshot.readUnits.flatMap(\.records))
        let unread = Set(snapshot.units.filter { $0.unitClass.isRead == false }.flatMap(\.records))
        #expect(counting.unitReads.count == 29)
        #expect(counting.unitReads.values.allSatisfy { $0 == 1 })
        #expect(Set(counting.recordReads.keys) == read)
        #expect(counting.recordReads.values.allSatisfy { $0 == 1 })
        #expect(counting.recordReads["Ring.swift-2NSB2P0UKUTYT"] == 1)
        #expect(read.isDisjoint(with: unread))
        #expect(unread.contains("Formatting.swift-3LDH9RDCYH116"))
        #expect(unread.contains("Relay.swift-2C7OPBZRU2SNG"))
        #expect(snapshot.records.map(\.name) == read.sorted())
    }

    @Test("the snapshot lists every unit with its class and counts each class")
    func classes() throws {
        let harness = try IndexWalkHarness.stale()

        let snapshot = try IndexWalk.walk(harness.source, filter: harness.filter)

        #expect(snapshot.units.map(\.name) == harness.units.map(\.name))
        #expect(snapshot.counts == [.kept: 22, .stale: 2, .otherPackage: 4])
        #expect(snapshot.readUnits.count == 22)
        #expect(snapshot.records.count == 22)
    }

    @Test("module names are target names wherever the module is the package's, and C99 names elsewhere")
    func moduleNames() throws {
        let harness = try IndexWalkHarness.fresh()

        let snapshot = try IndexWalk.walk(harness.source, filter: harness.filter)

        let units = Dictionary(uniqueKeysWithValues: snapshot.units.map { ($0.name, $0) })
        let support = try #require(units["Support.o-DGRO9MV486NA"])
        let kit = try #require(units["Kit.o-3SHEV4SLQQ5MS"])
        let tests = try #require(units["IndexCoreTests.o-X94YURMHJFQO"])
        let dependency = try #require(units["Dependency.o-2RBEW9CN17L3I"])
        let depKit = try #require(units["DepKit.o-3QG4QQUHJ0YQ0"])
        #expect(support.module == "index-support")
        #expect(support.isPackageModule)
        #expect(kit.module == "index-kit")
        #expect(tests.moduleDependencies.filter { $0.isSystem == false }.map(\.module) == [
            "IndexCore", "index-kit", "index-support"
        ])
        #expect(tests.moduleDependencies.filter(\.isSystem).map(\.module) == [
            "Swift", "Swift", "Swift", "Testing", "_SwiftConcurrencyShims"
        ])
        let imported = IndexUnitFact.ModuleDependency(module: "IndexDepKit", isSystem: false)
        #expect(dependency.moduleDependencies.first == imported)
        #expect(depKit.module == "IndexDepKit")
        #expect(depKit.isPackageModule == false)
    }

    @Test("paths under the root are paths in the package, and others stay absolute")
    func paths() throws {
        let harness = try IndexWalkHarness.fresh()

        let snapshot = try IndexWalk.walk(harness.source, filter: harness.filter)

        let units = Dictionary(uniqueKeysWithValues: snapshot.units.map { ($0.name, $0) })
        let record = try #require(snapshot.records.first { $0.name == "Support.swift-3FKQ6VEX8OPRR" })
        #expect(units["Support.o-DGRO9MV486NA"]?.path == "Sources/Kits/Support.swift")
        #expect(units["Support.o-DGRO9MV486NA"]?.triple == "arm64-apple-macos14.0")
        #expect(record.path == "Sources/Kits/Support.swift")
        #expect(units["DepKit.o-3QG4QQUHJ0YQ0"]?.path == harness.dependency + "/Sources/IndexDepKit/DepKit.swift")
        #expect(units["test_entry_point.o-27JSI56QYPVCU"]?.path.hasPrefix(".swiftstats/index-build/out/") == true)
        #expect(snapshot.records.allSatisfy { $0.path.hasPrefix("/") == false })
    }

    @Test("a unit or record that doesn't read fails the walk, naming it")
    func failures() throws {
        let harness = try IndexWalkHarness.fresh()
        let unitFailing = CountingIndexSource(harness.source, failing: [Self.ringName])
        let recordFailing = CountingIndexSource(harness.source, failing: ["Ring.swift-2NSB2P0UKUTYT"])

        #expect {
            try IndexWalk.walk(unitFailing, filter: harness.filter)
        } throws: { error in
            String(describing: error) == "unit \(Self.ringName) doesn't read: refused \(Self.ringName)"
        }
        #expect {
            try IndexWalk.walk(recordFailing, filter: harness.filter)
        } throws: { error in
            String(describing: error) == "record Ring.swift-2NSB2P0UKUTYT of unit \(Self.ringName) doesn't read: "
                + "refused Ring.swift-2NSB2P0UKUTYT"
        }
    }

    @Test("""
        the unit headers alone read every unit once and no record; the local USRs are those the read records \
        define with the local property: locals, local functions and parameters, not their enclosing function
        """)
    func headersAndLocals() throws {
        let harness = try IndexWalkHarness.fresh()
        let counting = CountingIndexSource(harness.source, failing: [])

        let units = try IndexWalk.units(of: counting)
        let locals = IndexAdapter.localUSRs(in: try IndexWalk.walk(harness.source, filter: harness.filter))

        #expect(units.count == harness.units.count && Set(units.map(\.name)) == Set(harness.units.map(\.name)))
        #expect(counting.recordReads.isEmpty)
        #expect(locals.contains("s:9IndexCore9summarizeySiSaySiGF11unusedTotalL_Sivp"))
        #expect(locals.contains("s:9IndexCore9summarizeySiSaySiGF12unusedHelperL_SiyF"))
        #expect(locals.contains("s:9IndexCore9summarizeySiSaySiGF6valuesL_ACvp"))
        #expect(locals.contains("s:9IndexCore9summarizeySiSaySiGF") == false)
        #expect(locals.contains("s:9IndexCore13onlyTestsCallSiyF") == false)
    }
}

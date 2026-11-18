//
//  InventoryFixtureTests.swift
//  SwiftStatsCoreTests
//
//  PRD M1b done-when (3): the Inventory fixture's counts, each worked out
//  by hand from its sources (see the comments), for the markers SwiftStats
//  finds itself, the API surface, and the test inventory.
//

import Foundation
import SwiftStatsCore
import Testing

@Suite("Inventory fixture")
struct InventoryFixtureTests {
    private static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Inventory")

    private static func scan() throws -> ScanReport {
        try PackageScanner(tools: .nowhere).scan(packageAt: fixture)
    }

    private static func rollup(_ name: String, in report: ScanReport) throws -> Rollup {
        try #require(report.rollups.first { $0.name == name })
    }

    @Test("SwiftStats' own markers: two IUOs, a precondition, a Task, an unsafe, a @MainActor, a test macro")
    func markers() throws {
        let report = try Self.scan()
        let markers = report.findings.filter { $0.tool == "swiftstats" }
        let placed = markers.map { "\($0.rule) \($0.locations[0].file):\($0.locations[0].line ?? 0)" }

        #expect(placed == [
            "implicitlyUnwrappedOptional Sources/Inventory/Store.swift:4",
            "precondition Sources/Inventory/Store.swift:8",
            "taskCreation Sources/Inventory/Store.swift:13",
            "mainActorDeclaration Sources/Inventory/Store.swift:19",
            "implicitlyUnwrappedOptional Sources/Inventory/Store.swift:21",
            "unsafeExpression Sources/Inventory/Store.swift:26",
            "propertyTestMacro Tests/InventoryTests/StoreTests.swift:32"
        ])
        // Lines 4 and 21 are stored properties, so they attach to their
        // types; 8, 13 and 26 are in function bodies.
        #expect(markers.map(\.locations[0].attachedTo) == [.type, .function, .function, .type, .type, .function, .type])
        let module = try Self.rollup("Inventory", in: report)
        // load() and reload() are async; Store is the one actor.
        #expect(module.asyncFunctions == 2)
        #expect(module.types["actor"] == 1)
        #expect(module.findings["swiftstats"] == [
            "implicitlyUnwrappedOptional": 2, "mainActorDeclaration": 1, "precondition": 1,
            "taskCreation": 1, "unsafeExpression": 1
        ])
    }

    @Test("API surface: eleven declarations, seven public, two of them documented")
    func apiSurface() throws {
        let api = try Self.rollup("Inventory", in: try Self.scan()).api

        // public: Store, items, load, Screen, title, init; open: Base;
        // internal: cache, refresh, show; private: reload.
        #expect(api.accessLevels == ["public": 6, "open": 1, "internal": 3, "private": 1])
        #expect(api.implicitlyInternal == 3)
        #expect(api.publicDeclarations == 7)
        // Store and load() have `///` comments.
        #expect(api.documentedPublicDeclarations == 2)
        // Screen (final) and Base.
        #expect(api.classes == 2)
        #expect(api.finalClasses == 1)
        #expect(api.overExposed == nil)
    }

    @Test("test inventory: eight tests by framework and kind, cases, assertions, generated left out")
    func testInventory() throws {
        let report = try Self.scan()
        let summary = try Self.rollup("InventoryTests", in: report).tests

        #expect(summary.tests == [
            "swift-testing": ["example": 1, "parameterized": 3, "property": 1, "idempotency": 1],
            "xctest": ["example": 2]
        ])
        // RoundTripStubs.swift is under Generated/ and has swift-infer's header.
        #expect(summary.generatedTests == 1)
        // save() and helperNotATest().
        #expect(summary.helpers == 2)
        // counts: 3; pairs: 5 × 2; modes: Mode.allCases can't be read.
        #expect(summary.parameterizedCases == 13)
        #expect(summary.parameterizedUnknownCases == 1)
        // Assertions per test: 1, 2, 1, 0, 1, 0 (Swift Testing), 2, 0 (XCTest).
        #expect(summary.assertionsPerTest == Distribution([1, 2, 1, 0, 1, 0, 2, 0]))
        #expect(summary.xctestWithoutAssertions == 1)
        #expect(summary.swiftTestingWithoutAssertions == nil)
        let roundTrip = try #require(report.tests.first { $0.key.hasSuffix("func roundTrip() async") })
        #expect(roundTrip.trials == 50)
        #expect(report.files.filter(\.generated).map(\.path) == [
            "Tests/InventoryTests/Generated/SwiftInfer/RoundTripStubs.swift"
        ])
    }

    @Test("line ratio: 25 test lines against 21 production lines")
    func lineRatio() throws {
        let report = try Self.scan()
        // Stripped lines per test, attribute-only lines left out:
        // emptyStore 3, counts 4, pairs 3, modes 1, roundTrip 5,
        // idempotentSave 3, testScreen 4, testNothing 2.
        let expected = LineRatio(
            testLines: 25,
            testLinesByKind: ["example": 9, "parameterized": 8, "property": 5, "idempotency": 3],
            productionLines: 21,
            deadCodeExcluded: false
        )

        #expect(try Self.rollup("InventoryTests", in: report).tests.lineRatio == expected)
        #expect(try Self.rollup("Inventory", in: report).tests.lineRatio == expected)
        #expect(try Self.rollup("tests", in: report).tests.lineRatio == expected)
    }
}

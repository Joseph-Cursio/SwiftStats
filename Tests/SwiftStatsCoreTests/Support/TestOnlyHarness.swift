//
//  TestOnlyHarness.swift
//  SwiftStatsCoreTests
//
//  A small package scanned with hand-made index results, for test-only
//  production code (M7, design §8.3): a library-product target `Lib`, a
//  library `Inner` in no product, an executable `Tool` and a test target
//  `LibTests`. Each production function gets the USR, reason, witness
//  flag and referrers a test gives it by name (its key's last segment);
//  the rest get a Swift USR and no referrers. The snapshot is stored and
//  read back, so the signal reads it as a report would.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// Stores the small package with hand-made index results.
enum TestOnlyHarness {
    /// A function's hand-made index facts.
    struct Facts {
        /// Its primary USR; nil for none.
        var usr: String?
        /// Why it has none.
        var reason: USRReason?
        /// Whether it witnesses or overrides something.
        var witness = false
        /// Distinct referrers in its own target.
        var sameModule = 0
        /// Distinct referrers in other production targets.
        var otherModules = 0
        /// Distinct referrers in test targets.
        var tests = 0
    }

    /// The package's files.
    static let files = [
        "Sources/Lib/Lib.swift": """
            public func api() -> Int { 1 }
            public func conformingAPI() -> Int { 2 }
            func conform() -> Int { 3 }
            func objcThing() -> Int { 4 }
            func objcWitness() -> Int { 5 }
            struct Fake {
                static func main() {}
            }
            final class Box {
                deinit {}
            }
            func onlyTests() -> Int { 6 }
            func alsoTests() -> Int { 7 }
            func fewTests() -> Int { 8 }
            func used() -> Int { 9 }
            func crossUsed() -> Int { 10 }
            func unused() -> Int { 11 }
            func flagged() -> Int { 12 }
            func topLevel() -> Int { 13 }
            func unjoined() -> Int { 14 }

            """,
        "Sources/Inner/Inner.swift": """
            public func helper() -> Int { 1 }

            """,
        "Sources/Tool/Tool.swift": """
            @main
            struct Tool {
                static func main() {}
                static func main(_ arguments: [String]) {}
                func main() {}
            }

            """,
        "Tests/LibTests/LibTests.swift": """
            func testAll() {
                _ = onlyTests()
            }

            """
    ]

    /// The package's targets.
    static let targets = [
        target("Inner", type: "library", path: "Sources/Inner"),
        target("Lib", type: "library", path: "Sources/Lib"),
        target("LibTests", type: "test", path: "Tests/LibTests"),
        target("Tool", type: "executable", path: "Sources/Tool")
    ]

    /// The test containers the index names of a record's referrers, at most.
    private static let namedReferrers = 5
    /// Two test referrers, as two of the listed cases have.
    private static let twoTests = 2
    /// Three test referrers, beside a production one.
    private static let threeTests = 3

    /// The library-product targets the index results name.
    static let libraryModules = ["Lib"]

    /// The facts every case of the test-only tests gives, by a key's last
    /// segment.
    static let cases: [String: Facts] = [
        "func api() -> Int": Facts(usr: "s:api", tests: 1),
        "func conformingAPI() -> Int": Facts(usr: "s:conformingAPI", witness: true, tests: 1),
        "func conform() -> Int": Facts(usr: "s:conform", witness: true, tests: 1),
        "func objcThing() -> Int": Facts(usr: "c:objc(cs)Thing", tests: 1),
        "func objcWitness() -> Int": Facts(usr: "c:objc(cs)Witness", witness: true, tests: 1),
        "static func main()": Facts(usr: "s:main", tests: 1),
        "static func main(_: [String])": Facts(usr: "s:mainArguments", tests: 1),
        "func main()": Facts(usr: "s:instanceMain"),
        "deinit": Facts(usr: "s:deinit", tests: 1),
        "func onlyTests() -> Int": Facts(usr: "s:onlyTests", tests: twoTests),
        "func alsoTests() -> Int": Facts(usr: "s:alsoTests", tests: twoTests),
        "func fewTests() -> Int": Facts(usr: "s:fewTests", tests: 1),
        "func used() -> Int": Facts(usr: "s:used", sameModule: 1, tests: threeTests),
        "func crossUsed() -> Int": Facts(usr: "s:crossUsed", otherModules: 1),
        "func unused() -> Int": Facts(usr: "s:unused"),
        "func flagged() -> Int": Facts(reason: .inactiveIfBranch),
        "func topLevel() -> Int": Facts(reason: .topLevelCode),
        "func helper() -> Int": Facts(usr: "s:helper", tests: 1)
    ]

    /// The Swift target `name` of `type` at `path`, holding the file
    /// named after it.
    private static func target(_ name: String, type: String, path: String) -> DescribedTarget {
        DescribedTarget(name: name, type: type, moduleType: "SwiftTarget", path: path, sources: ["\(name).swift"])
    }

    /// The package scanned at commit `c1`, holding index results with
    /// `facts` for the records whose key ends with each name (`unjoined()`
    /// has none, as if the index listed no record of its key), stored in
    /// `store` and read back.
    static func stored(_ facts: [String: Facts], in store: SnapshotStore) throws -> StoredSnapshot {
        let package = try TemporaryPackage(files, targets: targets)
        defer { package.remove() }
        let scanned = try SnapshotHarness.scan(package, commit: "c1")
        let records = scanned.report.records.compactMap { record -> IndexRecordUSR? in
            let name = record.key.components(separatedBy: "::").last ?? record.key
            guard name != "func unjoined() -> Int" else {
                return nil
            }
            let given = facts[name] ?? Facts(usr: "s:" + name)
            let references = IndexReferences(
                sameModule: given.sameModule,
                otherModules: given.otherModules,
                tests: given.tests,
                testReferrers: (0..<min(given.tests, namedReferrers)).map { "LibTests::func test\($0)()" }
            )
            return IndexRecordUSR(
                key: record.key,
                usr: given.usr,
                usrAccessor: nil,
                reason: given.usr == nil ? given.reason : nil,
                coupling: given.usr == nil ? nil : IndexRecordCoupling(witness: given.witness, references: references)
            )
        }
        let shell = try IndexStoreSamples.index(records: [])
        let index = IndexReport(
            store: shell.store,
            libraryModules: libraryModules,
            records: records,
            definitions: shell.definitions,
            disagreements: [],
            withoutRecord: [],
            collisions: [],
            moduleEdges: [],
            types: [],
            familyReferences: [],
            familyTypeReferences: [],
            files: []
        )
        let report = scanned.report.with(
            index: IndexRows.normalized(index),
            status: IndexStoreSamples.run(IndexAdapter.name, .ran).status
        )
        let snapshot = ScannedSnapshot(
            info: scanned.info.with(run: IndexStoreSamples.run(IndexAdapter.name, .ran)),
            report: report
        )
        return try store.load(id: try store.save(snapshot))
    }

    /// Test-only production code over `snapshot`.
    static func signal(_ snapshot: StoredSnapshot) throws -> SignalResult {
        try #require(
            SignalEngine.signals(of: SignalInputs(snapshot: snapshot), thresholds: SignalThresholds())
                .first { $0.name == .testOnlyProduction }
        )
    }

    /// What the signal decides of each of `snapshot`'s production
    /// functions, by key.
    static func verdicts(_ snapshot: StoredSnapshot) throws -> [String: TestOnlyProduction.Verdict] {
        let index = try #require(snapshot.index?.report)
        let judged = TestOnlyProduction.judged(SignalInputs(snapshot: snapshot), index: index)
        return Dictionary(judged.map { ($0.row.key, $0.verdict) }) { first, _ in first }
    }
}

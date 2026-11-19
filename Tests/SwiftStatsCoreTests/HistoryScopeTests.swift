import Foundation
@testable import SwiftStatsCore
import Testing

/// What history counts as the package's code and commits (PRD §7.13):
/// only files a target compiles, only commits that changed them, and a
/// package its commit doesn't hold yet is all uncommitted code.
@Suite("History scope")
struct HistoryScopeTests {
    /// A function `load` returning `value`.
    private static func store(_ value: Int) -> String {
        "func load(_ key: Int) -> Int {\n    key + \(value)\n}\n"
    }

    @Test("files no target compiles are neither tests nor part of a sweep")
    func uncompiledFiles() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write([
            "Sources/A/Store.swift": Self.store(0),
            "Tests/ATests/OtherTests.swift": "func testOther() {}\n",
            "Tests/Fixtures/Sample/Tests/X/StoreTests.swift": "func testStore() {}\n"
        ])
        try repository.commit("Add the store", day: 0)
        for step in 1...3 {
            try repository.write([
                "Sources/A/Store.swift": Self.store(step),
                "Tests/Fixtures/Sample/Tests/X/StoreTests.swift": "func testStore() { _ = \(step) }\n"
            ])
            try repository.commit("Change the store, \(step)", day: step)
        }
        var bulk = ["Sources/A/Store.swift": Self.store(9)]
        for index in 0..<31 {
            bulk["Tests/Fixtures/Bulk/Case\(index).swift"] = "func case\(index)() {}\n"
        }
        try repository.write(bulk)
        try repository.commit("Fix load", day: 5)
        let history = try repository.history()

        let load = try #require(history.family("func load(_: Int) -> Int"))

        #expect(load.hasTests == false)
        #expect(load.testChanges == 0)
        #expect(load.fixes == 1)
        #expect(load.sweepChanges == 0)
        #expect(history.sweepCommits.isEmpty)
        #expect(history.family("func testStore()") == nil)
    }

    @Test("commits that change none of the package's Swift files aren't counted or listed")
    func outOfScopeCommits() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write([
            "Sources/Lib/Store.swift": Self.store(0),
            "Packages/Inner/Package.swift": "// swift-tools-version: 6.0\n",
            "Packages/Inner/Sources/Inner/Inner.swift": "func inner() {}\n"
        ])
        try repository.commit("Add the code", day: 0)
        try repository.write(["README.md": "Fixed.\n"])
        try repository.commit("Fix the README", day: 1)
        try repository.write(["Packages/Inner/Sources/Inner/Inner.swift": "func inner() { _ = 1 }\n"])
        try repository.commit("Fix the inner package", day: 2)
        try repository.write(["Sources/Lib/Store.swift": Self.store(1)])
        try repository.commit("Change the store", day: 3)

        let history = try repository.history()

        #expect(history.commits == 2)
        #expect(history.windowCommits == 2)
        #expect(history.fixCommits.isEmpty)
    }

    @Test("a package its commit doesn't hold yet has history, and every function's is unknown")
    func packageNotCommitted() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write(["Sources/Outer/Outer.swift": "func outer() {}\n"])
        try repository.commit("Add the outer package", day: 0)
        try repository.write([
            "Packages/Inner/Package.swift": "// swift-tools-version: 6.0\n",
            "Packages/Inner/Sources/Inner/Inner.swift": "func inner() {}\n"
        ])

        let report = try repository.scanner().scan(
            packageAt: repository.root.appendingPathComponent("Packages/Inner"),
            configurationFile: nil,
            toolchain: SnapshotHarness.toolchain,
            date: SnapshotHarness.date
        ).report

        #expect(report.collectors.first { $0.name == HistoryCollector.name }?.state == .ran)
        let inner = try #require(report.history?.family("func inner()"))
        #expect(inner.changes == nil)
        #expect(inner.tracedBy == .uncommitted)
    }

    @Test(
        "a signed HEAD reads the same history when the user's git shows signatures",
        .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/ssh-keygen"))
    )
    func signedHead() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        let keys = try SnapshotHarness.temporaryDirectory("SigningKey")
        defer { try? FileManager.default.removeItem(at: keys) }
        let key = keys.appendingPathComponent("key")
        _ = try ProcessRunner.run(
            executable: "/usr/bin/ssh-keygen",
            arguments: ["-q", "-t", "ed25519", "-N", "", "-C", "tests", "-f", key.path],
            in: keys
        )
        try repository.git(["config", "gpg.format", "ssh"])
        try repository.git(["config", "user.signingkey", key.path])
        try repository.write(["Sources/Lib/Store.swift": Self.store(0)])
        try repository.commit("Add the store", day: 0, options: ["-S"])
        let plain = try repository.history()

        try repository.git(["config", "log.showSignature", "true"])

        #expect(try repository.history() == plain)
        #expect(plain.windowCommits == 1)
    }
}

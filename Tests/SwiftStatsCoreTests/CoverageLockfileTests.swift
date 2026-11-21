import Foundation
@testable import SwiftStatsCore
import Testing

/// The coverage run leaves the package's `Package.resolved` as it found it
/// (M5): SwiftPM resolves dependencies in the package root whatever the
/// scratch path, so the run puts the file's bytes back, or removes the
/// file, when it ends, however it ends, and an interruption does too.
@Suite("Coverage run and Package.resolved")
struct CoverageLockfileTests {
    /// What the fake build writes over `Package.resolved`.
    private static let rewritten = "{\n  \"pins\" : [],\n  \"version\" : 3\n}\n"
    /// A committed lockfile, with bytes a rewrite would change.
    private static let committed = Data("{\r\n  \"pins\" : [ ],\r\n  \"version\" : 2\r\n}".utf8)

    /// The lockfile of the package at `root`.
    private static func lockfile(of root: URL) -> URL {
        root.appendingPathComponent("Package.resolved")
    }

    /// The recorded scenario whose build writes `Package.resolved` in the
    /// package root, then exits with `status`.
    private static func writingScenario(status: Int32) throws -> FakeToolchain.Scenario {
        var scenario = try FakeToolchain.recorded()
        scenario.buildScript = "printf '%s' '\(rewritten)' > Package.resolved\n"
        scenario.buildStatus = status
        return scenario
    }

    @Test(
        "a build that writes Package.resolved leaves none when there was none, passing or failing",
        arguments: [Int32(0), 1]
    )
    func absentBefore(status: Int32) throws {
        try CoverageHarness.run(try Self.writingScenario(status: status)) { outcome in
            #expect(outcome.run.status.state == (status == 0 ? .ran : .failed))
            let calls = outcome.toolchain.calls(of: "swift")
            #expect(calls.contains { $0.hasPrefix("build\t--build-tests") })
            #expect(FileManager.default.fileExists(atPath: Self.lockfile(of: outcome.root).path) == false)
            #expect(ScratchRegistry.shared.preservedPaths.contains(Self.lockfile(of: outcome.root)) == false)
        }
    }

    @Test(
        "a build that rewrites Package.resolved leaves its bytes as they were, passing or failing",
        arguments: [Int32(0), 1]
    )
    func presentBefore(status: Int32) throws {
        let plant = { (root: URL) in try Self.committed.write(to: Self.lockfile(of: root)) }
        try CoverageHarness.run(try Self.writingScenario(status: status), arguments: [], prepare: plant) { outcome in
            #expect(outcome.run.status.state == (status == 0 ? .ran : .failed))
            let contents = try Data(contentsOf: Self.lockfile(of: outcome.root))
            #expect(contents == Self.committed)
        }
    }

    @Test("an interruption puts a preserved file back, or removes one that didn't exist")
    func interruption() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoverageLockfile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let present = directory.appendingPathComponent("Present/Package.resolved")
        let absent = directory.appendingPathComponent("Package.resolved")
        try FileManager.default.createDirectory(
            at: present.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.committed.write(to: present)
        let registry = ScratchRegistry()
        registry.preserve(try PreservedFile(url: present))
        registry.preserve(try PreservedFile(url: absent))
        try Data(Self.rewritten.utf8).write(to: present)
        try Data(Self.rewritten.utf8).write(to: absent)

        registry.cleanUp()

        #expect(try Data(contentsOf: present) == Self.committed)
        #expect(FileManager.default.fileExists(atPath: absent.path) == false)
        #expect(registry.preservedPaths.isEmpty)
    }
}

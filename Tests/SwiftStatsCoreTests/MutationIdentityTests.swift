import Foundation
@testable import SwiftStatsCore
import Testing

/// How a snapshot names the SwiftMutator build behind a run (M6, design
/// §1.1): the build its results header names, with the resolved binary's
/// commit as a label only when that binary is the build.
@Suite("Mutation identity")
struct MutationIdentityTests {
    /// How far past now the binary's modification date is set, so it is
    /// newer than its checkout's last commit and every tracked file.
    private static let builtAhead: TimeInterval = 60

    /// A `swift-mutator` in the `.build/release` of a clean checkout at
    /// `root`, newer than its commit and its tracked files, so its
    /// identity carries the commit.
    private static func cleanBuild(in root: URL) throws -> URL {
        try Data(".build/\n".utf8).write(to: root.appendingPathComponent(".gitignore"))
        try SnapshotHarness.runGit(["init", "-q"], in: root)
        try SnapshotHarness.runGit(["add", "-A"], in: root)
        try SnapshotHarness.runGit(["commit", "-q", "-m", "tool"], in: root)
        let release = root.appendingPathComponent(".build/release")
        try FileManager.default.createDirectory(at: release, withIntermediateDirectories: true)
        let binary = release.appendingPathComponent("swift-mutator")
        try Data("binary".utf8).write(to: binary)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(builtAhead)],
            ofItemAtPath: binary.path
        )
        return binary
    }

    /// The snapshot's record of a SwiftMutator run of `executable` whose
    /// results header named `reported`, in a scan that gave `report`.
    private static func info(reported: String, executable: URL, report: ScanReport) -> CollectorRunInfo {
        let skipped = CollectorStatus(
            name: EffectCollector.name,
            state: .skipped,
            version: nil,
            reason: "test",
            options: []
        )
        let ran = CollectorStatus(name: MutationAdapter.name, state: .ran, version: "0.1.0", reason: nil, options: [])
        let outcome = ScanOutcome(
            report: report,
            configuration: SwiftStatsConfiguration(),
            measureMilliseconds: 0,
            adapters: [
                TimedAdapterResult(
                    result: AdapterResult(status: ran, findings: [], warnings: []),
                    executable: executable,
                    identity: reported,
                    milliseconds: 0
                )
            ],
            effects: PackageScanner.EffectScan(facts: [:], summary: nil, status: skipped, milliseconds: 0),
            dependencies: PackageScanner.DependencyScan(
                report: report.dependencies,
                status: skipped,
                warnings: [],
                executable: nil,
                milliseconds: 0
            )
        )
        return SnapshotScanner.info(for: ran, outcome: outcome, toolchain: SnapshotHarness.toolchain)
    }

    @Test("""
        a run whose results header names the resolved binary's own hash keeps the binary's commit label; \
        one naming another build has none
        """)
    func labelWhenTheBinaryIsTheBuild() throws {
        let checkout = try SnapshotHarness.temporaryDirectory("MutatorCheckout")
        let package = try TemporaryPackage(["Sources/Lib/Lib.swift": "public func one() -> Int { 1 }\n"])
        defer {
            try? FileManager.default.removeItem(at: checkout)
            package.remove()
        }
        let binary = try Self.cleanBuild(in: checkout)
        let built = try #require(BinaryIdentity.of(binary))
        let label = try #require(built.label)
        let report = try package.scan(tools: SnapshotHarness.noTools)

        let same = Self.info(reported: built.identity, executable: binary, report: report)
        let other = Self.info(reported: MutationRunFailureTests.recordedBuild, executable: binary, report: report)

        #expect(label.hasPrefix("git:"))
        #expect(same.identity == built.identity)
        #expect(same.identityLabel == label)
        #expect(other.identity == MutationRunFailureTests.recordedBuild)
        #expect(other.identityLabel == nil)
    }
}

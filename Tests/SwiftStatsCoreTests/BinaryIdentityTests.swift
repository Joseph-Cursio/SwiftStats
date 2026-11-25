import Foundation
@testable import SwiftStatsCore
import Testing

/// An external tool's build identity (PRD §6.2): its binary's hash, with a
/// commit label only for a binary built in a clean checkout, and, for a
/// tool released by tag (outskirts, M7 design §1), the tag naming that
/// commit after it.
@Suite("Binary identity")
struct BinaryIdentityTests {
    /// How far past now a built binary's modification date is set, so it
    /// is newer than its checkout's last commit and every tracked file.
    private static let builtAhead: TimeInterval = 60

    /// A tool in the `.build/release` of a clean checkout at `root`, newer
    /// than its commit and its tracked files, the commit tagged `tag` when
    /// given; returns the tool and the commit.
    private static func cleanBuild(in root: URL, tag: String?) throws -> (tool: URL, commit: String) {
        try Data(".build/\n".utf8).write(to: root.appendingPathComponent(".gitignore"))
        try Data("// a tool\n".utf8).write(to: root.appendingPathComponent("main.swift"))
        try SnapshotHarness.runGit(["init", "-q"], in: root)
        try SnapshotHarness.runGit(["add", "-A"], in: root)
        try SnapshotHarness.runGit(["commit", "-q", "-m", "tool"], in: root)
        if let tag {
            try SnapshotHarness.runGit(["tag", tag], in: root)
        }
        let release = root.appendingPathComponent(".build/release")
        try FileManager.default.createDirectory(at: release, withIntermediateDirectories: true)
        let tool = release.appendingPathComponent("outskirts")
        try Data("binary".utf8).write(to: tool)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(builtAhead)],
            ofItemAtPath: tool.path
        )
        let commit = try #require(GitReader.line(["rev-parse", "HEAD"], in: root))
        return (tool, commit)
    }

    /// A scan outcome of `report` whose periphery run, recorded as
    /// `status`, ran `executable`.
    private static func outcome(_ report: ScanReport, executable: URL?, status: CollectorStatus) -> ScanOutcome {
        let skipped = CollectorStatus(
            name: EffectCollector.name,
            state: .skipped,
            version: nil,
            reason: "test",
            options: []
        )
        return ScanOutcome(
            report: report,
            configuration: SwiftStatsConfiguration(),
            measureMilliseconds: 0,
            adapters: [
                TimedAdapterResult(
                    result: AdapterResult(status: status, findings: [], warnings: []),
                    executable: executable,
                    identity: nil,
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
    }

    @Test("""
        a binary built in a clean tagged checkout is labelled with its commit and, when asked, the tag; a copy \
        of it outside the checkout has the same hash and no label
        """, .timeLimit(.minutes(1)))
    func taggedLabel() throws {
        let root = try SnapshotHarness.temporaryDirectory("TaggedTool")
        defer { try? FileManager.default.removeItem(at: root) }
        let built = try Self.cleanBuild(in: root, tag: "3.28.0")
        let copy = root.deletingLastPathComponent()
            .appendingPathComponent("outskirts-copy-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: built.tool, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }

        let tagged = try #require(BinaryIdentity.of(built.tool, tagged: true))
        let plain = try #require(BinaryIdentity.of(built.tool))
        let copied = try #require(BinaryIdentity.of(copy, tagged: true))

        #expect(tagged.label == "git:\(built.commit) (3.28.0)")
        #expect(plain.label == "git:\(built.commit)")
        #expect(tagged.identity == plain.identity && tagged.identity.hasPrefix("sha256:"))
        #expect(copied.identity == tagged.identity)
        #expect(copied.label == nil)
    }

    @Test(
        "a binary whose commit no tag names keeps the plain commit label when the tag is asked for",
        .timeLimit(.minutes(1))
    )
    func untaggedLabel() throws {
        let root = try SnapshotHarness.temporaryDirectory("UntaggedTool")
        defer { try? FileManager.default.removeItem(at: root) }
        let built = try Self.cleanBuild(in: root, tag: nil)

        let identity = try #require(BinaryIdentity.of(built.tool, tagged: true))

        #expect(identity.label == "git:\(built.commit)")
    }

    @Test("""
        the periphery collector's run is identified by its executable with the tag in its label; a skipped \
        run has no identity
        """, .timeLimit(.minutes(1)))
    func peripheryInfo() throws {
        let root = try SnapshotHarness.temporaryDirectory("PeripheryTool")
        defer { try? FileManager.default.removeItem(at: root) }
        let built = try Self.cleanBuild(in: root, tag: "3.28.0")
        let package = try TemporaryPackage(["Sources/Lib/Lib.swift": "public func one() -> Int { 1 }\n"])
        defer { package.remove() }
        let report = try package.scan(tools: SnapshotHarness.noTools)
        let ran = CollectorStatus(name: PeripheryAdapter.name, state: .ran, version: "3.28.0", reason: nil, options: [])
        let skipped = CollectorStatus(
            name: PeripheryAdapter.name,
            state: .skipped,
            version: nil,
            reason: "skipped",
            options: []
        )

        let info = SnapshotScanner.info(
            for: ran,
            outcome: Self.outcome(report, executable: built.tool, status: ran),
            toolchain: SnapshotHarness.toolchain
        )
        let unrun = SnapshotScanner.info(
            for: skipped,
            outcome: Self.outcome(report, executable: nil, status: skipped),
            toolchain: SnapshotHarness.toolchain
        )

        #expect(info.identity == BinaryIdentity.of(built.tool)?.identity)
        #expect(info.identityLabel == "git:\(built.commit) (3.28.0)")
        #expect(unrun.identity == nil && unrun.identityLabel == nil)
    }

    @Test("a binary outside any .build directory has a hash and no label", .timeLimit(.minutes(1)))
    func outsideBuild() throws {
        let tool = try FakeTool.make(outputs: [""], errorText: "", statuses: [0])
        defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }

        let identity = try #require(BinaryIdentity.of(tool))

        #expect(identity.identity.hasPrefix("sha256:"))
        #expect(identity.label == nil)
    }

    @Test("a binary in the .build of a directory that isn't a checkout has no label", .timeLimit(.minutes(1)))
    func buildOutsideGit() throws {
        let root = try SnapshotHarness.temporaryDirectory("BinaryIdentity")
        defer { try? FileManager.default.removeItem(at: root) }
        let release = root.appendingPathComponent("Tool/.build/release")
        try FileManager.default.createDirectory(at: release, withIntermediateDirectories: true)
        let tool = release.appendingPathComponent("tool")
        try Data("binary".utf8).write(to: tool)

        let identity = try #require(BinaryIdentity.of(tool))

        #expect(identity.label == nil)
    }
}

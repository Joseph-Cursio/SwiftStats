import Foundation
@testable import SwiftStatsCore
import Testing

/// An external tool's build identity (PRD §6.2): its binary's hash, with a
/// commit label only for a binary built in a clean checkout.
@Suite("Binary identity")
struct BinaryIdentityTests {
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

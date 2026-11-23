import Foundation
@testable import SwiftStatsCore
import Testing

/// Which SwiftMutator log `scan --mutation` names (M6, design §1.2): only
/// one its own mutation step wrote, never one an earlier scan left.
@Suite("Mutation log notice")
struct MutationLogNoticeTests {
    /// How far back a log an earlier scan left is dated.
    private static let earlier: TimeInterval = -3_600

    /// Dates the file at `url` an hour back, as a log an earlier scan left.
    private static func backdate(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(earlier)],
            ofItemAtPath: url.path
        )
    }

    /// The SwiftMutator collector's status in a stored scan of `harness`'s
    /// package that asked for a full run.
    private static func mutationStatus(_ harness: MutationRunHarness) throws -> CollectorRunInfo? {
        let workspace = try SnapshotWorkspace(
            packageRoot: harness.package.root,
            configurationFile: nil,
            storeOverride: nil,
            build: SnapshotHarness.build,
            describer: harness.package.describer,
            tools: SnapshotHarness.noTools
        )
        let stored = try workspace.scanWorkingTree(history: .skipped("test"), tiers: RequestedTiers(mutation: .full))
        return stored.snapshot.info.collectors.first { $0.name == MutationAdapter.name }
    }

    @Test("""
        the log is named after a mutation step wrote it, and not when the step was skipped or a log an earlier \
        scan left is all there is
        """)
    func namedOnlyWhenWritten() throws {
        let ran = try MutationRunHarness(try FakeMutator.recorded("full"))
        let disabled = try MutationRunHarness(try FakeMutator.recorded("full")) { _ in
            "collectors:\n  swiftmutator:\n    enabled: false\n"
        }
        defer {
            ran.remove()
            disabled.remove()
        }
        let stale = disabled.directory.appendingPathComponent(MutationDirectory.logName)
        try FileManager.default.createDirectory(at: disabled.directory, withIntermediateDirectories: true)
        try Data("an earlier scan's output\n".utf8).write(to: stale)
        try Self.backdate(stale)

        let beforeRun = Date()
        let run = ran.run()
        let written = StoreLocation.mutationLog(packageRoot: ran.package.root, writtenSince: beforeRun)
        try Self.backdate(ran.directory.appendingPathComponent(MutationDirectory.logName))
        let afterRun = Date()
        let leftOver = StoreLocation.mutationLog(packageRoot: ran.package.root, writtenSince: afterRun)
        let beforeSkip = Date()
        let skipped = try Self.mutationStatus(disabled)
        let notWritten = StoreLocation.mutationLog(packageRoot: disabled.package.root, writtenSince: beforeSkip)

        #expect(run.status.state == .ran)
        let log = try #require(written)
        #expect(MutationRunHarness.realPath(log) == MutationRunHarness.realPath(ran.directory) + "/swift-mutator.log")
        #expect(leftOver == nil)
        #expect(skipped?.reason == "disabled by collectors.swiftmutator.enabled")
        #expect(FileClone.exists(stale))
        #expect(notWritten == nil)
    }
}

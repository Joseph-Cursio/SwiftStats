import Foundation
@testable import SwiftStatsCore
import Testing

/// The T1 build's failure paths past the common ones (M7, design §1.3 and
/// §1.5) against a fake toolchain: a lock file that can't be locked for a
/// reason other than another holder, a describe whose output isn't a
/// package description, a description that can't be kept, root
/// intermediates that can't be removed, and a `Package.resolved` that can't
/// be put back, whose failure replaces the build's own.
@Suite("Build session failure paths")
struct BuildSessionFailurePathTests {
    /// The root intermediates folder of the package at `root` (real path),
    /// as the recorded describe names it.
    private static func intermediates(of root: URL) -> URL {
        root.appendingPathComponent(".swiftstats/index-build/out/Intermediates.noindex/IndexFixture.build")
    }

    @Test("""
        a lock file that can't be locked for a reason other than another holder fails the build naming that \
        reason, not another scan
        """)
    func lockUnsupported() throws {
        try BuildHarness.run(try FakeToolchain.recordedBuild()) { root in
            // A FIFO opens read-write, and flock(2) on it fails with ENOTSUP,
            // as on a volume without lock support.
            let lock = try StoreLocation.ignoreDirectory(packageRoot: root).appendingPathComponent("index.lock")
            try #require(mkfifo(lock.path, S_IRUSR | S_IWUSR) == 0)
        } check: { outcome in
            #expect(outcome.run.status.state == .failed)
            #expect(outcome.run.status.reason == "could not lock .swiftstats/index.lock: Operation not supported")
            #expect(outcome.swiftCalls == ["--version"])
        }
    }

    @Test("a describe that prints no package description fails the build, building nothing")
    func undecodableDescribe() throws {
        var scenario = try FakeToolchain.recordedBuild()
        scenario.describe = "not a package description\n"
        try BuildHarness.run(scenario) { outcome in
            #expect(outcome.run.status.state == .failed)
            let reason = try #require(outcome.run.status.reason)
            #expect(reason.hasPrefix(
                "`swift package --scratch-path <build> describe --type json` printed no package description "
                    + "SwiftStats reads: "
            ))
            #expect(outcome.built == false)
            #expect(outcome.run.log == nil)
        }
    }

    @Test("a description that can't be kept in the build directory fails the build, building nothing")
    func descriptionNotKept() throws {
        try BuildHarness.run(try FakeToolchain.recordedBuild()) { root in
            // A folder, not empty, where the description goes.
            let folder = root.appendingPathComponent(".swiftstats/index-build/swiftstats-describe.json/held")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } check: { outcome in
            #expect(outcome.run.status.state == .failed)
            let reason = try #require(outcome.run.status.reason)
            #expect(reason.hasPrefix("could not keep the package description: "))
            #expect(reason.contains(outcome.realRoot.path) == false)
            #expect(outcome.built == false)
        }
    }

    @Test("root intermediates that can't be removed fail the build rather than building on them")
    func intermediatesKept() throws {
        var locked: URL?
        defer {
            if let locked {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            }
        }
        try BuildHarness.run(try FakeToolchain.recordedBuild()) { root in
            let folder = Self.intermediates(of: root)
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent("held"),
                withIntermediateDirectories: true
            )
            // The parent can't be written, so the folder can't be removed.
            let parent = folder.deletingLastPathComponent()
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: parent.path)
            locked = parent
        } check: { outcome in
            if let locked {
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            }
            #expect(outcome.run.status.state == .failed)
            let reason = try #require(outcome.run.status.reason)
            #expect(reason.hasPrefix("could not remove the root package's intermediates: "))
            #expect(reason.contains(outcome.realRoot.path) == false)
            #expect(outcome.built == false)
            #expect(FileClone.exists(Self.intermediates(of: outcome.realRoot)))
        }
    }

    @Test("""
        a Package.resolved that can't be put back fails the run with that reason, in place of the build's own \
        failure
        """)
    func lockfileNotPutBack() throws {
        var scenario = try FakeToolchain.recordedBuild()
        // The build leaves a folder, not empty, where the file was.
        scenario.script = "rm -f Package.resolved\nmkdir -p Package.resolved/held\n"
        scenario.stderr = "error: no such module 'Missing'\n"
        scenario.status = 1
        try BuildHarness.run(scenario) { root in
            try Data("{}\n".utf8).write(to: root.appendingPathComponent("Package.resolved"))
        } check: { outcome in
            #expect(outcome.built)
            #expect(outcome.run.status.state == .failed)
            let reason = try #require(outcome.run.status.reason)
            #expect(reason.hasPrefix("could not put Package.resolved back as it was: "))
            #expect(reason.contains("no such module") == false)
            #expect(reason.contains(outcome.realRoot.path) == false)
        }
    }
}

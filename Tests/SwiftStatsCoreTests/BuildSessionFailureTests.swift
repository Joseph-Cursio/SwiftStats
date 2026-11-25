import Foundation
@testable import SwiftStatsCore
import Testing

/// What fails the T1 build (M7, design §1.5) against a fake toolchain: the
/// lock another scan holds, which the run keeps until its products are
/// read, a failing describe, a failing build, whose reason is its first
/// standard-error lines from the first error on, without timing or `info:`
/// lines, and a toolchain that refuses Swift Build.
@Suite("Build session failures")
struct BuildSessionFailureTests {
    /// The package at `root`'s `.swiftstats/index.lock`, its folder made.
    private static func lockFile(of root: URL) throws -> URL {
        try StoreLocation.ignoreDirectory(packageRoot: root).appendingPathComponent("index.lock")
    }

    /// Why `file`'s lock can't be taken now; nil when it can, after
    /// releasing it again.
    private static func refusal(taking file: URL) -> String? {
        do {
            try IndexLock(file: file).release()
            return nil
        } catch {
            return (error as? CoverageFailure)?.description ?? "\(error)"
        }
    }

    @Test("a second scan --index in the same package fails while the first holds the lock, building nothing")
    func lockHeld() throws {
        let toolchain = try FakeToolchain.make(build: try FakeToolchain.recordedBuild())
        defer { toolchain.remove() }
        let package = try TemporaryPackage(BuildHarness.files)
        defer { package.remove() }
        let lock = try Self.lockFile(of: package.root)

        let first = try IndexLock(file: lock)
        let held = BuildAdapter.run(swift: toolchain.proxy, root: package.root, files: []) { $0 }
        // The refused run leaves the first scan's lock held.
        let stillHeld = Self.refusal(taking: lock)
        first.release()

        // The toolchain is found first, then the lock stops the run.
        #expect(held.status.state == .failed)
        #expect(held.status.reason == "another scan --index is running in this package")
        #expect(held.identity == "swift:Apple Swift version 9.9 (fake)")
        #expect(toolchain.calls(of: "swift") == ["--version"])
        #expect(FileClone.exists(package.root.appendingPathComponent(".swiftstats/index-build")) == false)
        #expect(stillHeld == "another scan --index is running in this package")
        let released = BuildAdapter.run(swift: toolchain.proxy, root: package.root, files: []) { $0 }
        #expect(released.status.state == .ran)
    }

    @Test("""
        the lock stays held while the build's products are read, so a second scan --index can't take it \
        then, and is released once they have been
        """)
    func lockHeldWhileReading() throws {
        let toolchain = try FakeToolchain.make(build: try FakeToolchain.recordedBuild())
        defer { toolchain.remove() }
        let package = try TemporaryPackage(BuildHarness.files)
        defer { package.remove() }
        let lock = try Self.lockFile(of: package.root)

        let (run, whileReading) = BuildAdapter.run(swift: toolchain.proxy, root: package.root, files: []) { run in
            (run, Self.refusal(taking: lock))
        }

        #expect(run.status.state == .ran)
        #expect(run.products != nil)
        #expect(whileReading == "another scan --index is running in this package")
        #expect(Self.refusal(taking: lock) == nil)
    }

    @Test("a failing describe fails the build with its command, status and standard error, building nothing")
    func describeFails() throws {
        var scenario = try FakeToolchain.recordedBuild()
        scenario.failing = ["describe"]
        try BuildHarness.run(scenario) { outcome in
            #expect(outcome.run.status.state == .failed)
            #expect(outcome.run.status.reason
                == "`swift package --scratch-path <build> describe --type json` exited with status 1: "
                + "error: unable to describe")
            #expect(outcome.built == false)
            #expect(outcome.run.products == nil)
        }
    }

    @Test("a failing -print-target-info fails the build before anything else runs")
    func targetInfoFails() throws {
        var scenario = try FakeToolchain.recordedBuild()
        scenario.failing = ["print-target-info"]
        try BuildHarness.run(scenario) { outcome in
            #expect(outcome.run.status.state == .failed)
            #expect(outcome.run.status.reason
                == "`swift -print-target-info` exited with status 1: error: unable to load the target info")
            #expect(outcome.swiftCalls.isEmpty)
            #expect(outcome.run.identity == nil && outcome.run.executable == outcome.toolchain.proxy)
            #expect(outcome.run.status.options == [
                BuildAdapter.invocation, "rebuild: root package intermediates", ".swift-version: absent"
            ])
        }
    }

    @Test("""
        a build that exits non-zero fails with its standard error's first lines from the first error on, \
        -v's info: lines and timing lines left out, cleaned and redacted
        """)
    func failingBuild() throws {
        var scenario = try FakeToolchain.recordedBuild()
        scenario.stderr = try IndexFixture.text("failed.stderr")
        scenario.status = 1
        // Before its first error the recording holds -v's target graph,
        // the manifests' command lines and timing lines, which would
        // otherwise fill the reason.
        let recorded = scenario.stderr.split(whereSeparator: \.isNewline).map(String.init)
        let firstError = try #require(recorded.firstIndex { $0.hasPrefix("error: ") })
        try #require(recorded[..<firstError].contains { $0.hasPrefix("info: ") })
        try #require(recorded[..<firstError].contains { BuildLineGrammar.timingEntry($0) != nil })
        try BuildHarness.run(scenario) { outcome in
            #expect(outcome.run.status.state == .failed)
            #expect(outcome.run.products == nil)
            let reason = try #require(outcome.run.status.reason)
            let prefix = "swift build exited 1: "
            #expect(reason.hasPrefix(prefix))
            let lines = reason.dropFirst(prefix.count).split(separator: "\n").map(String.init)
            #expect(lines == [
                "error: <package>/Sources/IndexCore/Formatting.swift:8:1 expected expression in list of expressions "
                    + "[expected_expr_in_expr_list]",
                "warning: <package>/Sources/IndexCore/Warnings.swift:19:10 remember to finish this [pound_warning]",
                "error: SwiftDriver IndexCore normal arm64 com.apple.xcode.tools.swift.compiler failed with a nonzero "
                    + "exit code. Command line:",
                "error: Build failed"
            ])
            #expect(reason.contains("@ROOT@") == false && reason.contains(outcome.realRoot.path) == false)
            #expect(reason.contains(outcome.build.path) == false)
        }
    }

    @Test("""
        a failure's reason drops whole timing lines and info: lines, then keeps the first lines from the first \
        error line on
        """)
    func failureReason() {
        let text = "info: Target dependency graph (1 targets)\nCompiling Lib\n1.20ms\t/p/Sources/A.swift:1:1\t"
            + "global function Lib.(file).a()@/p/Sources/A.swift:1:1\n"
            + "0.10ms\t<invalid loc>\n2ms\tnot a place\n/p/Sources/A.swift:2:3: error: boom [id]\n"
            + "2 | boom()\n  | `- error: boom [id]\n0.20ms\t<invalid loc>\nerror: Build failed\n"

        let reason = BuildSession.failureReason(
            status: 2,
            stderr: text,
            replacing: [(URL(fileURLWithPath: "/p"), "<package>")]
        )

        #expect(reason == "swift build exited 2: <package>/Sources/A.swift:2:3: error: boom [id]\n"
            + "2 | boom()\n| `- error: boom [id]\nerror: Build failed")
        #expect(BuildSession.failureReason(status: 1, stderr: "0.5ms\t<invalid loc>\n", replacing: [])
            == "swift build exited 1")
    }

    @Test("""
        a failure's reason with no error line is its last lines, timing and info: lines left out; one with more \
        error lines than it keeps keeps the first
        """)
    func failureReasonBounds() {
        let unerrored = BuildSession.failureReason(
            status: 1,
            stderr: "info: Building targets in dependency order\nCompiling Lib\n0.5ms\t<invalid loc>\n"
                + "2ms\tnot a place\nwarning: something odd\n",
            replacing: []
        )
        let errors = (1...(CoverageStderr.keptLines + 10)).map { "error: failure \($0)" }
        let many = BuildSession.failureReason(
            status: 1,
            stderr: "Compiling Lib\n" + errors.joined(separator: "\n") + "\n",
            replacing: []
        )

        #expect(unerrored == "swift build exited 1: Compiling Lib\n2ms\tnot a place\nwarning: something odd")
        #expect(many == "swift build exited 1: " + errors.prefix(CoverageStderr.keptLines).joined(separator: "\n"))
    }

    @Test("a toolchain whose swift rejects --build-system swiftbuild fails, saying so in M5's words")
    func swiftBuildRefused() throws {
        var scenario = try FakeToolchain.recordedBuild()
        scenario.rejectsBuildSystem = true
        try BuildHarness.run(scenario) { outcome in
            #expect(outcome.run.status.state == .failed)
            #expect(outcome.run.status.reason
                == "this toolchain's swift doesn't accept `--build-system swiftbuild`, and the index build needs "
                + "Swift Build (Swift 6.2 or later): swift build exited 64: error: The value 'swiftbuild' is "
                + "invalid for '--build-system <build-system>'. Please provide one of 'native' and 'xcode'.\n"
                + "Usage: swift build <options>")
            #expect(outcome.swiftCalls.count == 3 && outcome.built)
        }
    }

    @Test("a build that fails without mentioning --build-system isn't taken for a refused Swift Build")
    func plainFailure() throws {
        var scenario = try FakeToolchain.recordedBuild()
        scenario.stderr = "error: no such module 'Missing'\n"
        scenario.status = 1
        try BuildHarness.run(scenario) { outcome in
            #expect(outcome.run.status.reason == "swift build exited 1: error: no such module 'Missing'")
        }
    }

    @Test("""
        a build that fails to compile, its standard error showing --build-system in a source snippet, \
        isn't taken for a refused Swift Build
        """)
    func snippetMentionsBuildSystem() throws {
        var scenario = try FakeToolchain.recordedBuild()
        scenario.stderr = """
            @ROOT@/Sources/IndexCore/Formatting.swift:2:1: error: cannot find 'missing' in scope [cannot_find_in_scope]
            1 | let flags = ["--build-system", "swiftbuild"]
            2 | missing()
              | `- error: cannot find 'missing' in scope [cannot_find_in_scope]
            error: Build failed

            """
        scenario.status = 1
        try BuildHarness.run(scenario) { outcome in
            let reason = try #require(outcome.run.status.reason)
            #expect(reason.hasPrefix(
                "swift build exited 1: <package>/Sources/IndexCore/Formatting.swift:2:1: error: cannot find"
            ))
            #expect(reason.contains("1 | let flags = [\"--build-system\", \"swiftbuild\"]"))
            #expect(reason.contains("doesn't accept") == false)
        }
    }
}

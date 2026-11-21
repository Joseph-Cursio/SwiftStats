import Foundation
@testable import SwiftStatsCore
import Testing

/// The coverage collector's run (M5) against a fake toolchain: the
/// toolchain it finds, the commands it runs, how it ties profiles to test
/// bundles, and one test per way it fails.
@Suite("Coverage run")
struct CoverageRunTests {
    /// The options every run on a package without a `.swift-version`
    /// records before its tools are known.
    private static let invocation = [
        "swift test --enable-code-coverage --scratch-path .swiftstats/coverage-build",
        "arguments: none",
        ".swift-version: absent"
    ]

    /// The options a run with the fake toolchain's own LLVM tools records
    /// for them.
    private static let llvmOptions = [
        "llvm tools: toolchain",
        "llvm-profdata: LLVM version 21.0.0",
        "llvm-cov: Apple LLVM version 21.0.0 (fake)"
    ]

    @Test("""
        a passing run finds the toolchain, builds and tests in .swiftstats/coverage-build, ties each bundle's \
        profiles to it by its runner, and exports every bundle
        """)
    func passingRun() throws {
        let scenario = try FakeToolchain.recorded()
        try CoverageHarness.run(scenario) { outcome in
            let status = outcome.run.status
            #expect(status.state == .ran)
            #expect(status.reason == nil)
            #expect(status.version == "Apple LLVM version 21.0.0 (fake)")
            #expect(status.options == Self.invocation + Self.llvmOptions + ["tests: passed"])
            #expect(outcome.run.identity == "swift:Apple Swift version 9.9 (fake)")
            #expect(outcome.run.executable == outcome.toolchain.swift)

            // The resolved swift is asked for the target info only; the
            // toolchain's own swift runs everything else.
            #expect(outcome.toolchain.calls(of: "proxy") == ["-print-target-info"])
            let swift = outcome.toolchain.calls(of: "swift")
            let build = outcome.build.path
            let flags = "--enable-code-coverage\t--scratch-path\t\(build)"
            #expect(Array(swift.prefix(4)) == [
                "--version", "build\t--show-bin-path\t\(flags)",
                "build\t--build-tests\t\(flags)", "test\t--skip-build\t\(flags)"
            ])
            #expect(swift.count == 5 && swift[4].hasPrefix("demangle\t--compact\t"))
            let ignore = outcome.root.appendingPathComponent(".swiftstats/.gitignore")
            #expect((try? String(contentsOf: ignore, encoding: .utf8)) == "*\n")

            let profiles = try #require(outcome.run.profiles)
            #expect(profiles.bundles == ["ProbeTests", "SwiftTestKitTests"])
            #expect(profiles.testStatus == 0 && profiles.hasExtraProfiles == false)
            let export = try String(contentsOf: profiles.export, encoding: .utf8)
            #expect(profiles.export.path == "\(build)/swiftstats-export.json")
            #expect(export.contains("@ROOT@") == false && export.contains("/Sources/Probe/Counter.swift"))
            let exports = outcome.toolchain.calls(of: "llvm-cov").filter { $0.hasPrefix("export") }
            let probe = outcome.bin.appendingPathComponent("ProbeTests.xctest/Contents/MacOS/ProbeTests").path
            let kit = outcome.bin
                .appendingPathComponent("SwiftTestKitTests.xctest/Contents/MacOS/SwiftTestKitTests").path
            #expect(exports == ["export\t-instr-profile\t\(build)/swiftstats.profdata\t\(probe)\t-object\t\(kit)"])
        }
    }

    @Test("""
        each test target's counts come from its own processes' profiles, with a source path before a \
        private function's, a closure's or a property initializer's name dropped
        """)
    func perTargetCounts() throws {
        try CoverageHarness.run(try FakeToolchain.recorded()) { outcome in
            let counts = try #require(outcome.run.profiles?.counts)
            let probe = try #require(counts["ProbeTests"])
            let kit = try #require(counts["SwiftTestKitTests"])
            #expect(probe["$s5Probe5twice33_45327D15D096802744EACB638966501CLLyS2iF"] == 2)
            #expect(probe["$s5Probe7CounterV3addyySaySiGFS2iXEfU_"] == 2)
            #expect(probe["$s5Probe7CounterV5totalSivpfi"] == 2)
            #expect(probe["$s5Probe7CounterV7doubledSiyF"] == 2)
            #expect(probe["$s5Probe7onlyKitSiyF"] == nil)
            #expect(kit["$s5Probe7onlyKitSiyF"] == 1)
            #expect(kit["$s5Probe7CounterV7doubledSiyF"] == nil)
            #expect(probe.keys.allSatisfy { $0.hasPrefix("$s") } && kit.keys.allSatisfy { $0.hasPrefix("$s") })
        }
    }

    @Test("collectors.coverage.arguments follow swift test's own flags and are recorded verbatim")
    func arguments() throws {
        let arguments = ["--skip", "SlowTests", "--skip", "Perf.*"]
        let pin = { (root: URL) in
            try "6.4.1\n".write(to: root.appendingPathComponent(".swift-version"), atomically: true, encoding: .utf8)
        }
        try CoverageHarness.run(try FakeToolchain.recorded(), arguments: arguments, prepare: pin) { outcome in
            let test = outcome.toolchain.calls(of: "swift").first { $0.hasPrefix("test\t") }
            #expect(test?.hasSuffix("\t--skip\tSlowTests\t--skip\tPerf.*") == true)
            #expect(outcome.run.status.options.prefix(3) == [
                "swift test --enable-code-coverage --scratch-path .swiftstats/coverage-build",
                "arguments: --skip SlowTests --skip Perf.*",
                ".swift-version: 6.4.1"
            ])
        }
    }

    @Test("without llvm-profdata and llvm-cov beside swift, the run takes them from xcrun --find and says so")
    func xcrunFallback() throws {
        var scenario = try FakeToolchain.recorded()
        scenario.llvmInToolchain = false
        try CoverageHarness.run(scenario) { outcome in
            #expect(outcome.run.status.state == .ran)
            #expect(outcome.run.status.options.contains("llvm tools: xcrun"))
            #expect(outcome.toolchain.calls(of: "xcrun") == ["--find\tllvm-profdata", "--find\tllvm-cov"])
            #expect(outcome.toolchain.calls(of: "llvm-cov").contains { $0.hasPrefix("export\t") })
        }

        scenario.failing = ["xcrun"]
        #expect(try CoverageHarness.failure(scenario)
            == "`xcrun --find llvm-profdata` exited with status 1: xcrun: error: unable to find utility")
    }

    @Test("without the LLVM tools in the toolchain and no xcrun on PATH, the run fails saying so")
    func noXcrun() throws {
        var scenario = try FakeToolchain.recorded()
        scenario.llvmInToolchain = false
        let toolchain = try FakeToolchain.make(scenario)
        defer { toolchain.remove() }
        let package = try TemporaryPackage(["Sources/Lib/Lib.swift": "public func one() -> Int { 1 }\n"])
        defer { package.remove() }

        let run = CoverageAdapter.run(swift: toolchain.proxy, root: package.root, arguments: [], locator: .nowhere)

        #expect(run.status.state == .failed)
        #expect(run.status.reason
            == "the toolchain has no llvm-profdata and llvm-cov, and `xcrun` was not found on PATH")
        #expect(run.status.options == Self.invocation)
        #expect(run.identity == nil && run.profiles == nil)
    }

    @Test("""
        a test bundle of a removed test target, and the profiles of an earlier run, are cleared before the \
        build, so neither is read
        """)
    func staleBundle() throws {
        let plant = { (root: URL) in
            let bin = CoverageHarness.bin(of: root)
            let removed = bin.appendingPathComponent("RemovedTests.xctest/Contents/MacOS")
            try FileManager.default.createDirectory(at: removed, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: removed.appendingPathComponent("RemovedTests"))
            let codecov = bin.appendingPathComponent("codecov")
            try FileManager.default.createDirectory(at: codecov, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: codecov.appendingPathComponent("XCTest1_0.9.profraw"))
            try Data("x".utf8).write(to: root.appendingPathComponent(".swiftstats/coverage-build/1.profdata"))
        }
        try CoverageHarness.run(try FakeToolchain.recorded(), arguments: [], prepare: plant) { outcome in
            #expect(outcome.run.status.state == .ran)
            #expect(outcome.run.status.reason == nil)
            #expect(outcome.run.profiles?.bundles == ["ProbeTests", "SwiftTestKitTests"])
            let merges = outcome.toolchain.calls(of: "llvm-profdata").filter { $0.hasPrefix("merge") }
            #expect(merges.allSatisfy { $0.contains("XCTest1_0.9") == false })
            let stale = outcome.root.appendingPathComponent(".swiftstats/coverage-build/1.profdata")
            #expect(FileManager.default.fileExists(atPath: stale.path) == false)
        }
    }

    @Test("""
        a failed build fails the run with the command and its standard error cleaned, and the earlier run's \
        profiles are gone, not read
        """)
    func buildFailure() throws {
        var scenario = try FakeToolchain.recorded()
        scenario.buildStatus = 1
        scenario.buildError = """
            error: @ROOT@/Sources/Lib/Lib.swift:1:21 expected parameter name followed by ':'
            error: SwiftDriver Lib normal arm64 com.apple.xcode.tools.swift.compiler failed with a nonzero exit \
            code. Command line:     cd @ROOT@
                builtin-SwiftDriver -- swiftc -module-name Lib \(String(repeating: "-I @BUILD@/x ", count: 500))
            error: Build failed

            """
        let plant = { (root: URL) in
            let codecov = CoverageHarness.bin(of: root).appendingPathComponent("codecov")
            try FileManager.default.createDirectory(at: codecov, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: codecov.appendingPathComponent("XCTest1_0.9.profraw"))
        }
        try CoverageHarness.run(scenario, arguments: [], prepare: plant) { outcome in
            #expect(outcome.run.status.state == .failed)
            #expect(outcome.run.status.reason == """
                `swift build --build-tests --enable-code-coverage --scratch-path <build>` exited with status 1: \
                error: <package>/Sources/Lib/Lib.swift:1:21 expected parameter name followed by ':'
                error: SwiftDriver Lib normal arm64 com.apple.xcode.tools.swift.compiler failed with a nonzero exit \
                code. Command line:
                error: Build failed
                """)
            #expect(outcome.run.status.options == Self.invocation + Self.llvmOptions)
            #expect(outcome.run.identity == "swift:Apple Swift version 9.9 (fake)")
            let codecov = outcome.bin.appendingPathComponent("codecov")
            #expect(FileManager.default.fileExists(atPath: codecov.path) == false)
            #expect(outcome.toolchain.calls(of: "llvm-profdata").allSatisfy { $0.hasPrefix("merge") == false })
            #expect(outcome.toolchain.calls(of: "swift").contains { $0.hasPrefix("test") } == false)
        }
    }

    @Test("a package with no test target fails the run, and its tests are never run")
    func noBundles() throws {
        var scenario = try FakeToolchain.recorded()
        scenario.bundles = []
        try CoverageHarness.run(scenario) { outcome in
            #expect(outcome.run.status.reason == "no test bundle was built (the package has no test targets)")
            #expect(outcome.toolchain.calls(of: "swift").contains { $0.hasPrefix("test") } == false)
        }
    }

    @Test("failing tests with every profile present still run the collector, merged from the profiles")
    func failingTests() throws {
        var scenario = try FakeToolchain.recorded()
        scenario.testStatus = 1
        try CoverageHarness.run(scenario) { outcome in
            #expect(outcome.run.status.state == .ran)
            #expect(outcome.run.status.reason
                == "tests failing (swift test exited 1); coverage merged from the test processes' profiles")
            #expect(outcome.run.status.options.last == "tests: failing")
            #expect(outcome.run.profiles?.testStatus == 1)
        }
    }

    @Test("""
        an exit test's extra profile is merged; with failing tests the reason warns that a crash after it \
        may have gone unseen
        """)
    func extraProfiles() throws {
        var scenario = try FakeToolchain.recorded()
        let kit = CoverageHarness.signature(of: "SwiftTestKitTests", in: scenario)
        scenario.profiles.append(("Swift Testing\(kit)_0.99999.profraw", 1))
        try CoverageHarness.run(scenario) { outcome in
            #expect(outcome.run.status.state == .ran && outcome.run.status.reason == nil)
            #expect(outcome.run.profiles?.hasExtraProfiles == true)
            let merges = outcome.toolchain.calls(of: "llvm-profdata").filter { $0.hasPrefix("merge") }
            #expect(merges.filter { $0.contains("_0.99999.profraw") }.count == 2)
        }

        scenario.testStatus = 1
        try CoverageHarness.run(scenario) { outcome in
            #expect(outcome.run.status.reason == """
                tests failing (swift test exited 1); coverage merged from the test processes' profiles; a test \
                process may have crashed after an exit test, so coverage may be incomplete
                """)
        }
    }

    @Test("swift test exiting non-zero with no profile at all fails the run with its standard error, not as a crash")
    func testsWroteNothing() throws {
        var scenario = try FakeToolchain.recorded()
        scenario.profiles = []
        scenario.testStatus = 1
        scenario.testError = "error: no tests found at @BUILD@/out/Products/Debug\n"
        #expect(try CoverageHarness.failure(scenario) == """
            `swift test --skip-build --enable-code-coverage --scratch-path <build>` exited with status 1: \
            error: no tests found at <build>/out/Products/Debug
            """)
    }
}

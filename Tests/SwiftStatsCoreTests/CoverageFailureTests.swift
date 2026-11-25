import Foundation
@testable import SwiftStatsCore
import Testing

/// How the coverage collector's run fails (M5) when a test process writes
/// no profile, a profile can't be tied to its bundle, the toolchain can't
/// be used, an earlier run's files can't be cleared, or one of its tools
/// fails or can't be run: one test per path, against a fake toolchain.
@Suite("Coverage run failures")
struct CoverageFailureTests {
    /// The recorded scenario without the profile of `framework`'s process
    /// for `bundle`.
    private static func without(_ framework: String, of bundle: String) throws -> FakeToolchain.Scenario {
        var scenario = try FakeToolchain.recorded()
        let prefix = "\(framework)\(CoverageHarness.signature(of: bundle, in: scenario))_"
        scenario.profiles.removeAll { $0.name.hasPrefix(prefix) }
        return scenario
    }

    /// The recorded scenario changed as `knob` names: target info without
    /// the runtime resource path, a toolchain without its own `swift`, an
    /// `xcrun --find` or a `swift build --show-bin-path` printing nothing,
    /// or a failing `swift --version`.
    private static func scenario(_ knob: String) throws -> FakeToolchain.Scenario {
        var scenario = try FakeToolchain.recorded()
        switch knob {
        case "target info":
            scenario.targetInfo = "{\"paths\":{\"runtimeLibraryPaths\":[]}}\n"
        case "no swift":
            scenario.swiftInToolchain = false
        case "silent xcrun":
            scenario.llvmInToolchain = false
            scenario.silent = ["xcrun"]
        case "silent bin path":
            scenario.silent = ["show-bin-path"]
        default:
            scenario.failing = [knob]
        }
        return scenario
    }

    /// The status of a coverage run acting out `scenario` on a fresh
    /// package, and the calls of each fake tool.
    private static func outcome(
        _ scenario: FakeToolchain.Scenario
    ) throws -> (status: CollectorStatus, calls: [String: [String]]) {
        let toolchain = try FakeToolchain.make(scenario)
        defer { toolchain.remove() }
        let package = try TemporaryPackage(["Sources/Lib/Lib.swift": "public func one() -> Int { 1 }\n"])
        defer { package.remove() }
        let run = CoverageAdapter.run(
            swift: toolchain.proxy,
            root: package.root,
            arguments: [],
            locator: toolchain.locator
        )
        let calls = Dictionary(uniqueKeysWithValues: ["swift", "llvm-profdata", "llvm-cov"].map { tool in
            (tool, toolchain.calls(of: tool))
        })
        return (run.status, calls)
    }

    @Test("""
        a crashed Swift Testing process leaves its bundle's group no runner; the group is tied to the bundle \
        by elimination and the reason names it
        """)
    func swiftTestingCrash() throws {
        var scenario = try Self.without("Swift Testing", of: "SwiftTestKitTests")
        // The XCTest process of a bundle with no XCTest tests runs nothing
        // of its test module.
        scenario.shows[CoverageHarness.signature(of: "SwiftTestKitTests", in: scenario)] = """
            Counters:
              $s5Probe7onlyKitSiyF:
                Hash: 0x0000000000000000
                Counters: 1
                Function count: 0
                Block counts: []
            """
        let outcome = try Self.outcome(scenario)
        #expect(outcome.status.reason
            == "the Swift Testing test process for SwiftTestKitTests wrote no profile (it crashed or was killed)")
        #expect(outcome.status.options.last == "llvm-cov: Apple LLVM version 21.0.0 (fake)")
        #expect(outcome.calls["llvm-cov"]?.contains { $0.hasPrefix("export") } == false)
    }

    @Test("""
        two crashed Swift Testing processes are each tied to their bundle by a counted function of its test \
        module, and the reason names the first bundle
        """)
    func crashesTiedByModule() throws {
        var scenario = try FakeToolchain.recorded()
        for bundle in scenario.bundles {
            let signature = CoverageHarness.signature(of: bundle, in: scenario)
            scenario.profiles.removeAll { $0.name.hasPrefix("Swift Testing\(signature)_") }
            scenario.shows[signature] = """
                Counters:
                  $s\(bundle.count)\(bundle)4testyyF:
                    Function count: 1
                """
        }
        #expect(try CoverageHarness.failure(scenario)
            == "the Swift Testing test process for ProbeTests wrote no profile (it crashed or was killed)")
    }

    @Test("a crashed XCTest process is named by its bundle, found from what its Swift Testing process ran")
    func xcTestCrash() throws {
        let scenario = try Self.without("XCTest", of: "ProbeTests")
        #expect(try CoverageHarness.failure(scenario)
            == "the XCTest test process for ProbeTests wrote no profile (it crashed or was killed)")
    }

    @Test("a 0-byte profile counts as none, and is never merged")
    func emptyProfile() throws {
        var scenario = try FakeToolchain.recorded()
        let kit = CoverageHarness.signature(of: "SwiftTestKitTests", in: scenario)
        let index = try #require(scenario.profiles.firstIndex { $0.name.hasPrefix("Swift Testing\(kit)_") })
        scenario.profiles[index].size = 0
        let outcome = try Self.outcome(scenario)
        #expect(outcome.status.reason
            == "the Swift Testing test process for SwiftTestKitTests wrote no profile (it crashed or was killed)")
        let merges = outcome.calls["llvm-profdata"]?.filter { $0.hasPrefix("merge") } ?? []
        #expect(merges.allSatisfy { $0.contains(scenario.profiles[index].name) == false })
    }

    @Test("""
        a group no rule ties to a bundle is named by its signature: missing a framework's profile, or \
        complete but one of two such groups
        """)
    func untiedGroups() throws {
        var crashed = try FakeToolchain.recorded()
        for bundle in crashed.bundles {
            let signature = CoverageHarness.signature(of: bundle, in: crashed)
            crashed.profiles.removeAll { $0.name.hasPrefix("Swift Testing\(signature)_") }
            crashed.shows[signature] = "Counters:\n"
        }
        let first = try #require(FakeToolchain.recordedSignatures().first)
        #expect(try CoverageHarness.failure(crashed)
            == "the Swift Testing test process with signature \(first) wrote no profile (it crashed or was killed)")

        var extra = try FakeToolchain.recorded()
        extra.bundles = ["ProbeTests"]
        extra.profiles += [("XCTest1_0.1.profraw", 1), ("Swift Testing1_0.2.profraw", 1)]
        #expect(try CoverageHarness.failure(extra)
            == "the profiles with signature 1 could not be tied to a test bundle")
    }

    @Test("a profile whose name doesn't follow the grammar fails the run, naming it")
    func unknownProfileName() throws {
        var scenario = try FakeToolchain.recorded()
        scenario.profiles.append(("default.profraw", 1))
        #expect(try CoverageHarness.failure(scenario)
            == "the profile default.profraw doesn't follow <XCTest|Swift Testing><signature>_<n>.<pid>.profraw")
    }

    @Test(
        "a failing merge, show, export, demangle, target info or bin path fails the run with the command, redacted",
        arguments: [
            ("merge", "`llvm-profdata merge -sparse (2 profiles) -o <build>/"),
            ("show", "`llvm-profdata show --all-functions --counts <build>/"),
            ("export", "`llvm-cov export -instr-profile <build>/swiftstats.profdata (2 bundles)` exited with status 1"),
            ("demangle", "`swift demangle --compact (4 names)` exited with status 1: error: unable to demangle"),
            ("print-target-info", "`swift -print-target-info` exited with status 1: error: unable to load the target"),
            (
                "show-bin-path",
                "`swift build --show-bin-path --build-system swiftbuild --enable-code-coverage --scratch-path <build>` "
                    + "exited"
            )
        ]
    )
    func toolFailure(step: String, expected: String) throws {
        var scenario = try FakeToolchain.recorded()
        scenario.failing = [step]
        let reason = try #require(try CoverageHarness.failure(scenario))
        #expect(reason.hasPrefix(expected))
        #expect(reason.contains("/private/") == false && reason.contains("/var/") == false)
        if step == "merge" {
            #expect(reason.hasSuffix(": error: <package>/x.profraw: invalid instrumentation profile data"))
        }
    }

    @Test(
        "a toolchain or bin path the run can't use fails it, saying why without an absolute path",
        arguments: [
            ("target info", "`swift -print-target-info` printed no paths.runtimeResourcePath"),
            ("no swift", "`swift -print-target-info` names a toolchain with no `swift` beside its runtime resources"),
            ("silent xcrun", "`xcrun --find llvm-profdata` printed no path"),
            (
                "silent bin path",
                "`swift build --show-bin-path --build-system swiftbuild --enable-code-coverage --scratch-path <build>` "
                    + "printed no path"
            ),
            ("version", "`swift --version` exited with status 1: error: unable to print the version")
        ]
    )
    func unusableToolchain(knob: String, expected: String) throws {
        let reason = try CoverageHarness.failure(try Self.scenario(knob))
        #expect(reason == expected)
    }

    @Test("""
        without the LLVM tools in the toolchain, a missing or failing xcrun is reported before a failing \
        swift --version, which isn't run
        """)
    func xcrunBeforeVersion() throws {
        var scenario = try FakeToolchain.recorded()
        scenario.llvmInToolchain = false
        scenario.failing = ["version"]
        let toolchain = try FakeToolchain.make(scenario)
        defer { toolchain.remove() }
        let package = try TemporaryPackage(["Sources/Lib/Lib.swift": "public func one() -> Int { 1 }\n"])
        defer { package.remove() }
        let run = CoverageAdapter.run(swift: toolchain.proxy, root: package.root, arguments: [], locator: .nowhere)
        #expect(run.status.reason
            == "the toolchain has no llvm-profdata and llvm-cov, and `xcrun` was not found on PATH")
        #expect(toolchain.calls(of: "swift").contains("--version") == false)

        scenario.failing = ["version", "xcrun"]
        #expect(try CoverageHarness.failure(scenario)
            == "`xcrun --find llvm-profdata` exited with status 1: xcrun: error: unable to find utility")
    }

    @Test("an earlier run's file that can't be removed fails the run before the build, its path redacted")
    func staleFileStays() throws {
        let codecov = { (root: URL) in CoverageHarness.bin(of: root).appendingPathComponent("codecov") }
        let plant = { (root: URL) in
            try FileManager.default.createDirectory(at: codecov(root), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: codecov(root).appendingPathComponent("XCTest1_0.9.profraw"))
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: codecov(root).path)
        }
        try CoverageHarness.run(try FakeToolchain.recorded(), arguments: [], prepare: plant) { outcome in
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codecov(outcome.root).path)
            #expect(outcome.run.status.state == .failed)
            // Foundation words the rest, in the system's language.
            let reason = try #require(outcome.run.status.reason)
            #expect(reason.hasPrefix("could not clear what an earlier run left: ") && reason.contains("codecov"))
            #expect(reason.contains("/private/") == false && reason.contains("/var/") == false)
            #expect(outcome.toolchain.calls(of: "swift").contains { $0.hasPrefix("build\t--build-tests") } == false)
        }
    }

    @Test("an export file that can't be created fails the run with the export command, its path redacted")
    func exportFileUncreatable() throws {
        var scenario = try FakeToolchain.recorded()
        scenario.testScript = "mkdir -p \"$scratch/swiftstats-export.json\"\n"
        #expect(try CoverageHarness.failure(scenario) == """
            `llvm-cov export -instr-profile <build>/swiftstats.profdata (2 bundles)` could not be run: \
            could not create <build>/swiftstats-export.json
            """)
    }

    @Test("a resolved swift that can't be started fails the run naming the tool, never its path")
    func unstartableSwift() throws {
        let package = try TemporaryPackage(["Sources/Lib/Lib.swift": "public func one() -> Int { 1 }\n"])
        defer { package.remove() }
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoToolchain-\(UUID().uuidString)/bin/swift")

        let run = CoverageAdapter.run(
            swift: missing,
            root: package.root,
            arguments: [],
            locator: .nowhere
        )

        #expect(run.status.state == .failed)
        let reason = try #require(run.status.reason)
        #expect(reason.hasPrefix("`swift -print-target-info` could not be run: "))
        #expect(reason.contains("NoToolchain-") == false && reason.contains("/var/") == false)
    }
}

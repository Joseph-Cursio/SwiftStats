import Foundation
@testable import SwiftStatsCore
import Testing

/// The coverage run's build layout (M5) against a fake toolchain: every
/// SwiftPM command asks for Swift Build, whose bundles are one per test
/// target; a toolchain that can't, or a bundle that is no test target,
/// fails the run instead of linking no test to anything. And the runner
/// rule ties a group to its bundle from `swift demangle`'s output.
@Suite("Coverage build layout")
struct CoverageLayoutTests {
    /// A counted function record of `llvm-profdata show`, for `name`.
    private static func record(_ name: String) -> String {
        """
          \(name):
            Hash: 0x0000000000000000
            Counters: 1
            Function count: 1
            Block counts: []

        """
    }

    @Test("show-bin-path, the build and the tests each pass --build-system swiftbuild, and the options record it")
    func buildSystemFlag() throws {
        try CoverageHarness.run(try FakeToolchain.recorded()) { outcome in
            #expect(outcome.run.status.state == .ran)
            #expect(outcome.run.status.options.first == """
                swift test --build-system swiftbuild --enable-code-coverage --scratch-path .swiftstats/coverage-build
                """)
            let swiftPM = outcome.toolchain.calls(of: "swift")
                .filter { $0.hasPrefix("build\t") || $0.hasPrefix("test\t") }
            #expect(swiftPM.count == 3)
            #expect(swiftPM.allSatisfy { $0.contains("\t--build-system\tswiftbuild\t") })
        }
    }

    @Test("""
        a merged <Package>PackageTests bundle, as the native build system makes, fails the run naming it, \
        before the tests run
        """)
    func mergedBundle() throws {
        // Native builds one bundle, whose processes share one signature:
        // elimination alone would tie that group to it.
        var scenario = try FakeToolchain.recorded()
        let probe = CoverageHarness.signature(of: "ProbeTests", in: scenario)
        scenario.bundles = ["CoverageProbePackageTests"]
        scenario.testTargets = ["ProbeTests", "SwiftTestKitTests"]
        scenario.profiles.removeAll { $0.name.contains(probe) == false }
        try CoverageHarness.run(scenario) { outcome in
            #expect(outcome.run.status.state == .failed)
            #expect(outcome.run.status.reason == """
                coverage needs Swift Build's test bundles, one per test target, but the build made \
                CoverageProbePackageTests.xctest, which is no test target of the package
                """)
            #expect(outcome.run.profiles == nil)
            #expect(outcome.toolchain.calls(of: "swift").contains { $0.hasPrefix("test") } == false)
        }
    }

    @Test("""
        the test targets come from the toolchain's own swift package describe; a bundle it doesn't list fails \
        the run
        """)
    func toolchainDescription() throws {
        var scenario = try FakeToolchain.recorded()
        scenario.testTargets = ["ProbeTests"]
        try CoverageHarness.run(scenario) { outcome in
            #expect(outcome.run.status.state == .failed)
            #expect(outcome.run.status.reason == """
                coverage needs Swift Build's test bundles, one per test target, but the build made \
                SwiftTestKitTests.xctest, which is no test target of the package
                """)
            #expect(outcome.toolchain.calls(of: "swift").contains { $0.hasPrefix("test") } == false)
        }
    }

    @Test("a failing swift package describe fails the run, saying so, before the tests run")
    func describeFails() throws {
        var scenario = try FakeToolchain.recorded()
        scenario.failing = ["describe"]
        try CoverageHarness.run(scenario) { outcome in
            #expect(outcome.run.status.state == .failed)
            #expect(outcome.run.status.reason == """
                `swift package --scratch-path <build> describe --type json` exited with status 1: \
                error: unable to describe
                """)
            #expect(outcome.toolchain.calls(of: "swift").contains { $0.hasPrefix("test") } == false)
        }
    }

    @Test("bundles are matched to test targets by c99 module name, and every unknown bundle is named")
    func unknownBundles() {
        #expect(CoverageBundles.unknownBundles(["My_Tests", "Other"], testTargets: ["My-Tests", "Other"]) == nil)
        #expect(CoverageBundles.unknownBundles(["Gone", "Kept", "Extra"], testTargets: ["Kept"]) == """
            coverage needs Swift Build's test bundles, one per test target, but the build made Extra.xctest and \
            Gone.xctest, which are no test targets of the package
            """)
    }

    @Test("a toolchain whose swift rejects --build-system swiftbuild fails the run, saying what it needs")
    func buildSystemRejected() throws {
        var scenario = try FakeToolchain.recorded()
        scenario.rejectsBuildSystem = true
        try CoverageHarness.run(scenario) { outcome in
            #expect(outcome.run.status.state == .failed)
            #expect(outcome.run.status.reason == """
                this toolchain's swift doesn't accept `--build-system swiftbuild`, and coverage needs Swift Build's \
                test bundles, one per test target (Swift 6.2 or later): `swift build --show-bin-path --build-system \
                swiftbuild --enable-code-coverage --scratch-path <build>` exited with status 64: error: The value \
                'swiftbuild' is invalid for '--build-system <build-system>'. Please provide one of 'native' and \
                'xcode'.
                Usage: swift build <options>
                """)
            #expect(outcome.toolchain.calls(of: "swift").contains { $0.hasPrefix("build\t--build-tests") } == false)
        }
    }

    @Test("""
        a group whose counted functions name both test modules is tied only by its runner, from swift demangle's \
        output, the substituted spelling included
        """)
    func runnerOnlyTie() throws {
        var scenario = try FakeToolchain.recorded()
        let probe = CoverageHarness.signature(of: "ProbeTests", in: scenario)
        let kit = CoverageHarness.signature(of: "SwiftTestKitTests", in: scenario)
        // Each group also counts a function of the other test module, so the
        // module rule finds two bundles for each, and elimination two groups.
        let kitTest = Self.record("$s17SwiftTestKitTests04onlyC4RunsyyF")
        let probeTest = Self.record("$s10ProbeTests7nestingyyF")
        scenario.shows[probe] = try #require(scenario.shows[probe])
            .replacingOccurrences(of: "Counters:\n", with: "Counters:\n" + kitTest)
        scenario.shows[kit] = try #require(scenario.shows[kit])
            .replacingOccurrences(of: "Counters:\n", with: "Counters:\n" + probeTest)
        try CoverageHarness.run(scenario) { outcome in
            #expect(outcome.run.status.state == .ran)
            #expect(outcome.run.status.reason == nil)
            let counts = try #require(outcome.run.profiles?.counts)
            #expect(counts["ProbeTests"]?["$s10ProbeTests28__SwiftPMGeneratedTestRunnerV4mainyyYaFZ"] == 1)
            #expect(counts["SwiftTestKitTests"]?["$s17SwiftTestKitTests02__a11PMGeneratedB6RunnerV4mainyyYaFZ"] == 1)
        }
    }
}

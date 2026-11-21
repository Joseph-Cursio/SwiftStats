import Foundation
@testable import SwiftStatsCore
import Testing

/// The pieces of the coverage run (M5) that read tool output: profile
/// names, `llvm-profdata show` text and its names, the runner and test
/// module rules that tie profiles to bundles, LLVM version lines, and the
/// cleaning of a failed command's standard error.
@Suite("Coverage profiles")
struct CoverageProfileTests {
    /// SIP's real runner names, as `llvm-profdata show` printed them: the
    /// mangler substitutes `Swift`, and in `SwiftInferTestLifterTests`
    /// also `Test`, so neither spells `__SwiftPMGeneratedTestRunner`.
    private static let sipRunners = [
        "@ROOT@/.build/out/Intermediates.noindex/SwiftInferProperties.build/Debug/SwiftInferKitEvidenceTests-p.build/"
            + "DerivedSources/test_entry_point.swift:"
            + "$s26SwiftInferKitEvidenceTests02__A21PMGeneratedTestRunnerV14testingLibrary"
            + "33_63166DBCF0ED362DE4378CDC40BF8555LLSSyFZ",
        "$s24SwiftInferTemplatesTests02__A21PMGeneratedTestRunnerV4mainyyYaFZ",
        "$s25SwiftInferTestLifterTests02__a11PMGeneratedC6RunnerV4mainyyYaFZ"
    ]

    /// A group of `signature` whose functions ran `counts` times.
    private static func group(_ signature: String, _ counts: [String: Int64]) -> CoverageGroup {
        let profiles = CoverageProfile.frameworks.compactMap { framework in
            CoverageProfile(url: URL(fileURLWithPath: "/b/codecov/\(framework)\(signature)_0.1.profraw"), size: 1)
        }
        return CoverageGroup(signature: signature, profiles: profiles, counts: counts)
    }

    @Test("a profile's name gives its framework and signature; any other name, or an empty file, is told apart")
    func profileNames() {
        let swiftTesting = CoverageProfile(
            url: URL(fileURLWithPath: "/b/codecov/Swift Testing13691672633913768854_0.4711.profraw"),
            size: 3_000_000
        )
        let xcTest = CoverageProfile(url: URL(fileURLWithPath: "/b/XCTest42_1.7.profraw"), size: 0)

        #expect(swiftTesting?.framework == "Swift Testing" && swiftTesting?.signature == "13691672633913768854")
        #expect(swiftTesting?.isEmpty == false)
        #expect(xcTest?.framework == "XCTest" && xcTest?.signature == "42" && xcTest?.isEmpty == true)
        for name in ["default.profraw", "XCTest42.profraw", "XCTestabc_0.1.profraw", "Swift Testing42_0.1.profdata"] {
            #expect(CoverageProfile(url: URL(fileURLWithPath: "/b/\(name)"), size: 1) == nil)
        }
    }

    @Test("""
        a show name keeps only the mangled name after a source path, whatever separates them, and any other \
        name stays as it is
        """)
    func normalisedNames() {
        #expect(ProfileShow.normalized("/p/Sources/X/File.swift:$s5Probe7AccountC7watchedSivpfi")
            == "$s5Probe7AccountC7watchedSivpfi")
        #expect(ProfileShow.normalized("/p/a:b/File.swift:_$s5Probe1fyyF") == "_$s5Probe1fyyF")
        #expect(ProfileShow.normalized("/p/File.swift;$S5Probe1fyyF") == "$S5Probe1fyyF")
        #expect(ProfileShow.normalized("$s5Probe1fyyF") == "$s5Probe1fyyF")
        #expect(ProfileShow.normalized("-[Foo bar:baz:]") == "-[Foo bar:baz:]")
        #expect(ProfileShow.normalized("/p/file.c:helper") == "/p/file.c:helper")
    }

    @Test("""
        show text gives each record's entry count by its normalised name, a count past Int64.max kept at the \
        maximum and a repeated name at its larger count
        """)
    func showCounts() {
        let text = """
            Counters:
              /p/Sources/Probe/Counter.swift:$s5Probe7CounterV3addyySaySiGFS2iXEfU_:
                Hash: 0x0000000000000000
                Counters: 1
                Function count: 2
                Block counts: []
              $s5Probe7CounterV7doubledSiyF:
                Hash: 0x0000000000000000
                Counters: 1
                Function count: 18446744073709551615
                Block counts: []
              $s5Probe1fyyF:
                Function count: 3
              /q/Other.swift:$s5Probe1fyyF:
                Function count: 1
            Instrumentation level: Front-end
            Functions shown: 4
            Maximum function count: 9
            """

        #expect(ProfileShow.counts(text) == [
            "$s5Probe7CounterV3addyySaySiGFS2iXEfU_": 2,
            "$s5Probe7CounterV7doubledSiyF": Int64.max,
            "$s5Probe1fyyF": 3
        ])
    }

    @Test("SIP's runner names, in both of the mangler's spellings, are picked for demangling, and nothing else is")
    func runnerCandidates() {
        let names = Self.sipRunners.map(ProfileShow.normalized) + ["$s14SwiftInferCore4plainyyF"]
        let group = Self.group("1", Dictionary(uniqueKeysWithValues: names.map { ($0, Int64(1)) }))
        let unrun = Self.group("2", ["$s20SwiftInferMacroTests02__A21PMGeneratedTestRunnerV4mainyyYaFZ": 0])

        #expect(CoverageBundles.runnerCandidates(in: [group, unrun]) == names.dropLast().sorted())
    }

    @Test("a demangled runner name gives its target, and no other demangled name gives one")
    func runnerTargets() {
        #expect(CoverageBundles.runnerTarget(
            in: "static SwiftInferTestLifterTests.__SwiftPMGeneratedTestRunner.main() async -> ()"
        ) == "SwiftInferTestLifterTests")
        #expect(CoverageBundles.runnerTarget(
            in: "static ProbeTests.__SwiftPMGeneratedTestRunner.(testingLibrary in _F434)() -> Swift.String"
        ) == "ProbeTests")
        #expect(CoverageBundles.runnerTarget(in: "Probe.Counter.doubled() -> Swift.Int") == nil)
        #expect(CoverageBundles.runnerTarget(in: ".__SwiftPMGeneratedTestRunner.main()") == nil)
    }

    @Test("""
        groups are tied to bundles by runner, then by a counted function of the test module, then by \
        elimination; a bundle two groups claim goes to neither
        """)
    func owners() {
        let runner = "$s5ATests02__A21PMGeneratedTestRunnerV4mainyyYaFZ"
        let groups = [
            Self.group("1", [runner: 1]),
            Self.group("2", ["$s6BTests4testyyF": 1, "$s5ATests4testyyF": 0]),
            Self.group("3", ["$s5Probe1fyyF": 1])
        ]
        let demangled = [runner: "static ATests.__SwiftPMGeneratedTestRunner.main() async -> ()"]

        #expect(CoverageBundles.owners(of: groups, bundles: ["ATests", "BTests", "CTests"], demangled: demangled)
            == ["1": "ATests", "2": "BTests", "3": "CTests"])
        let twice = [Self.group("1", ["$s6BTests1fyyF": 1]), Self.group("2", ["$s6BTests1gyyF": 1])]
        #expect(CoverageBundles.owners(of: twice, bundles: ["BTests", "CTests"], demangled: [:]).isEmpty)
        let leading = [Self.group("1", ["_$s6BTests1fyyF": 1]), Self.group("2", [:])]
        #expect(CoverageBundles.owners(of: leading, bundles: ["BTests", "CTests"], demangled: [:])
            == ["1": "BTests", "2": "CTests"])
    }

    @Test("""
        a bundle whose test target's name isn't an identifier is tied by its module's c99 name, by runner and by \
        test module alike
        """)
    func c99BundleNames() {
        #expect(CoverageBundles.moduleName(of: "ProbeTests") == "ProbeTests")
        #expect(CoverageBundles.moduleName(of: "my-lib-tests") == "my_lib_tests")
        #expect(CoverageBundles.moduleName(of: "2fast tests") == "_fast_tests")
        #expect(CoverageBundles.moduleName(of: "Café.Tests") == "Café_Tests")

        let runner = "$s12my_lib_tests31__SwiftPMGeneratedTestRunnerV4mainyyYaFZ"
        let groups = [
            Self.group("1", [runner: 1]),
            Self.group("2", ["$s11_fast_tests4testyyF": 1]),
            Self.group("3", [:])
        ]
        let demangled = [runner: "static my_lib_tests.__SwiftPMGeneratedTestRunner.main() async -> ()"]
        #expect(CoverageBundles.owners(
            of: groups,
            bundles: ["my-lib-tests", "2fast-tests", "OtherTests"],
            demangled: demangled
        ) == ["1": "my-lib-tests", "2": "2fast-tests", "3": "OtherTests"])
    }

    @Test("an LLVM tool's version is its line naming the LLVM version, for swift.org's tools and Xcode's alike")
    func versionLines() {
        let swiftOrg = "LLVM (http://llvm.org/):\n  LLVM version 21.0.0\n  Optimized build.\n"
        #expect(CoverageToolchain.versionLine(of: swiftOrg) == "LLVM version 21.0.0")
        #expect(CoverageToolchain.versionLine(of: "Apple LLVM version 21.0.0\n  Optimized build.\n")
            == "Apple LLVM version 21.0.0")
        #expect(CoverageToolchain.versionLine(of: "llvm-cov 22\n\n  experimental\n") == "llvm-cov 22; experimental")
    }

    @Test("""
        a failed command's standard error loses its command lines, keeps the located error, is redacted, \
        cut to 300 characters a line and to its last 20 lines
        """)
    func cleanedStderr() {
        let root = URL(fileURLWithPath: "/work/Package")
        let build = root.appendingPathComponent(".swiftstats/coverage-build")
        let replacements = [(build, "<build>"), (root, "<package>")]
        let link = """
            error: /work/Package/Sources/Lib/Broken.swift:1:21 expected parameter name followed by ':'
            error: SwiftDriver Lib normal arm64 failed with a nonzero exit code. Command line:     cd /work
                builtin-SwiftDriver -- swiftc -module-name Lib
                -I /work/Package/.swiftstats/coverage-build/out
            \(String(repeating: " -L/work/Package/.swiftstats/coverage-build/lib", count: 150))
            Undefined symbols for architecture arm64:
              "_missing", referenced from:
            ld: symbol(s) not found for architecture arm64
            \(String(repeating: "w", count: 400))
            """

        let cleaned = CoverageStderr.cleaned(link, replacing: replacements)

        #expect(cleaned == """
            error: <package>/Sources/Lib/Broken.swift:1:21 expected parameter name followed by ':'
            error: SwiftDriver Lib normal arm64 failed with a nonzero exit code. Command line:
            Undefined symbols for architecture arm64:
            "_missing", referenced from:
            ld: symbol(s) not found for architecture arm64
            \(String(repeating: "w", count: 300))…
            """)
        // An indented line over 1,000 characters is dropped wherever it is;
        // one of 999 is kept, cut like any other.
        let lone = """
            ld: warning: ignoring duplicate libraries
            \(" " + String(repeating: "x", count: 1_000))
            \(" " + String(repeating: "y", count: 998))
            error: Ld failed
            """
        #expect(CoverageStderr.cleaned(lone, replacing: []) == """
            ld: warning: ignoring duplicate libraries
            \(String(repeating: "y", count: 300))…
            error: Ld failed
            """)
        let many = (1...30).map { "error: \($0)" }.joined(separator: "\n")
        #expect(CoverageStderr.cleaned(many, replacing: []).split(separator: "\n").first == "error: 11")
        #expect(CoverageStderr.cleaned(many, replacing: []).split(separator: "\n").count == 20)
    }
}

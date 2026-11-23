import Foundation
@testable import SwiftStatsCore
import Testing

/// The SwiftMutator collector's run (M6, design §1.2 to §1.8), through the
/// fake tools acting out recorded runs of the Mutation fixture: the
/// status, identity and options a run that ran records, the results file
/// and report it keeps, the copy it removes and the build it keeps, and
/// the commands, arguments and configuration it gives SwiftMutator.
@Suite("Mutation run")
struct MutationRunTests {
    /// The SwiftMutator build the recordings name.
    static let recordedBuild = "5138cbf1b810b127accddd8d4973bb2675195797cbae9b734bd09c0ae5a35ba8"

    @Test("""
        a full run that ran takes its version, identity and options from the results file's header, keeps the \
        results and report in runs/<id>/, removes the copy and keeps the build
        """)
    func ranFull() throws {
        let scenario = try FakeMutator.recorded("full")
        let harness = try MutationRunHarness(scenario)
        defer { harness.remove() }

        let run = harness.run()

        #expect(run.status.state == .ran)
        #expect(run.status.reason == nil)
        #expect(run.status.version == "0.1.0")
        #expect(run.identity == "sha256:\(Self.recordedBuild)")
        #expect(run.status.options == [
            "swift-mutator run -c .swiftstats/mutation/muter.conf.yml --skip-update-check",
            "arguments: none",
            "timeout: default",
            ".swift-version: absent",
            "toolchain: Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1)",
            "test executable: unrecorded",
            "sdk environment: none",
            "operators: ChangeArithmeticOperator, ChangeLogicalConnector, FlipBooleanLiteral, NegateConditional, "
                + "RelationalBoundary, RelationalOperatorReplacement, RemoveSideEffects, ReplaceBooleanValue, "
                + "ReplaceReturnValue, SwapTernary",
            "coverage: on"
        ])
        let results = try #require(run.results)
        #expect(results.complete)
        #expect(results.facts.mutantsDiscovered == 35)
        #expect(run.suspects.suspectsChecked == false)
        #expect(run.warnings.isEmpty)

        let kept = try #require(run.resultsFile)
        let keptURL = harness.package.root.appendingPathComponent(kept)
        let bytes = try Data(contentsOf: keptURL)
        #expect(kept == ".swiftstats/mutation/runs/\(ContentHash.sha256(bytes).prefix(16))/results.jsonl")
        #expect(ContentHash.sha256(bytes) == results.sha256)
        let project = harness.realProject
        let expected = try #require(scenario.results)
            .replacingOccurrences(of: "@ROOT@", with: project)
            .replacingOccurrences(of: "@PARENT@", with: URL(fileURLWithPath: project).deletingLastPathComponent().path)
        #expect(String(bytes: bytes, encoding: .utf8) == expected)
        let report = keptURL.deletingLastPathComponent().appendingPathComponent("report.json")
        #expect(try SuspectReport.decode(Data(contentsOf: report)) == run.suspects)

        #expect(FileClone.exists(harness.directory.appendingPathComponent("work")) == false)
        let builds = harness.directory.appendingPathComponent("build-cache/builds.txt")
        #expect(try String(contentsOf: builds, encoding: .utf8) == "built\n")
    }

    @Test("""
        SwiftMutator runs in the copy with NO_COLOR, nothing on standard input, an absolute -c outside the copy and \
        --skip-update-check, never --since or --changed-lines in a full run, and the report reads its results file
        """)
    func commandLines() throws {
        let harness = try MutationRunHarness(try FakeMutator.recorded("full"))
        defer { harness.remove() }

        _ = harness.run()

        let calls = harness.fake.calls(of: "swift-mutator")
        try #require(calls.count == 2)
        let configuration = harness.directory.appendingPathComponent("muter.conf.yml").path
        #expect(calls[0] == ["run", "-c", configuration, "--skip-update-check"])
        #expect(calls[0].contains("--changed-lines") == false && calls[0].contains("--since") == false)
        #expect(calls[1].count == 6)
        #expect(calls[1].first == "report")
        #expect(calls[1][1].hasSuffix("_muter_logs/\(FakeMutator.folder)/results.jsonl"))
        #expect(Array(calls[1][2...4]) == ["-f", "json", "-o"])
        #expect(calls[1][5].hasSuffix(".swiftstats/mutation/work/report.json"))
        #expect(harness.fake.calls(of: "swift") == [["build", "--build-tests"]])

        let project = harness.realProject
        for tool in ["swift-mutator", "swift"] {
            #expect(Set(harness.fake.facts("cwd", of: tool)) == [project])
            #expect(Set(harness.fake.facts("env", of: tool)) == ["1"])
            #expect(Set(harness.fake.facts("stdin", of: tool)) == ["empty"])
        }
        let log = try String(contentsOf: harness.directory.appendingPathComponent("swift-mutator.log"), encoding: .utf8)
        #expect(log.contains("=== swiftstats: swift build --build-tests exited 0 after "))
        #expect(log.contains("=== swiftstats: swift-mutator run exited 0 after "))
        #expect(log.contains("💾 Each mutant's result is in "))
    }

    @Test("""
        the configuration's test command is swift test with collectors.swiftmutator.arguments, every value \
        double-quoted, and options.workers and options.timeout become --workers and --timeout
        """)
    func configurationAndOptions() throws {
        let harness = try MutationRunHarness(try FakeMutator.recorded("full"))
        defer { harness.remove() }
        let settings = CollectorSettings(
            enabled: true,
            path: harness.fake.mutator.path,
            arguments: ["--skip", "a \"b\": c\\d|e"],
            workers: 3,
            timeout: 2.5
        )

        let run = harness.run(settings: settings)

        let configuration = harness.directory.appendingPathComponent("muter.conf.yml").path
        let call = try #require(harness.fake.calls(of: "swift-mutator").first)
        #expect(call == ["run", "-c", configuration, "--skip-update-check", "--workers", "3", "--timeout", "2.5"])
        #expect(harness.fake.configuration == """
            executable: "\(harness.fake.swift.path)"
            arguments:
            - "test"
            - "--skip"
            - "a \\"b\\": c\\\\d|e"
            exclude: []
            excludeCalls: []

            """)
        #expect(run.status.options.prefix(3) == [
            "swift-mutator run -c .swiftstats/mutation/muter.conf.yml --skip-update-check",
            "arguments: --skip a \"b\": c\\d|e",
            "timeout: 2.5"
        ])
        #expect(MutationAdapter.seconds(30) == "30")
    }

    @Test("a full and a since run of the same settings record the same options, so they compare")
    func optionsAcrossModes() throws {
        let full = try MutationFixture.results(of: "full", in: MutationFixture.directory)
        let since = try MutationFixture.results(of: "since", in: MutationFixture.directory)

        #expect(since.facts.since != nil)
        #expect(MutationAdapter.options(of: full.facts) == MutationAdapter.options(of: since.facts))
        #expect(MutationAdapter.identity(of: full.facts) == MutationAdapter.identity(of: since.facts))
        #expect(MutationAdapter.sdkEnvironment(["SDKROOT": "/a", "DEVELOPER_DIR": "/b"])
            == "sha256:" + ContentHash.sha256(Data("DEVELOPER_DIR=/b\nSDKROOT=/a\n".utf8)))
    }

    @Test("the build in build-cache/ survives runs, moved into each run's copy and back")
    func buildCache() throws {
        let harness = try MutationRunHarness(try FakeMutator.recorded("full"))
        defer { harness.remove() }

        let first = harness.run()
        let second = harness.run()

        #expect(first.status.state == .ran && second.status.state == .ran)
        let builds = harness.directory.appendingPathComponent("build-cache/builds.txt")
        #expect(try String(contentsOf: builds, encoding: .utf8) == "built\nbuilt\n")
        // The same results again are the same run, kept once.
        #expect(first.resultsFile != nil && first.resultsFile == second.resultsFile)
    }
}

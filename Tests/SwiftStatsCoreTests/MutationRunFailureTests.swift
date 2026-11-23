import Foundation
@testable import SwiftStatsCore
import Testing

/// What stops or weakens a SwiftMutator run before or after SwiftMutator
/// itself (M6, design §1.2 to §1.4): another scan holding the lock, a
/// failing warm build, a results path that disagrees with the log folder,
/// a failing report and results lines that don't read; and which `swift`
/// and build identity a run uses.
@Suite("Mutation run failures")
struct MutationRunFailureTests {
    /// The SwiftMutator build the recordings name.
    static let recordedBuild = "sha256:5138cbf1b810b127accddd8d4973bb2675195797cbae9b734bd09c0ae5a35ba8"

    @Test("a second scan --mutation in the same package fails while the first holds the lock, running nothing")
    func lockHeld() throws {
        let harness = try MutationRunHarness(try FakeMutator.recorded("full"))
        defer { harness.remove() }
        let directory = try MutationDirectory(packageRoot: harness.package.root)

        let run = try MutationLock.holding(directory.lock) { () -> MutationRun in
            harness.run()
        }

        #expect(run.status.state == .failed)
        #expect(run.status.reason == "another scan --mutation is running in this package")
        #expect(harness.fake.calls(of: "swift").isEmpty && harness.fake.calls(of: "swift-mutator").isEmpty)
        #expect(harness.run().status.state == .ran)
    }

    @Test("a warm build that fails fails the run with its last lines, the copy redacted, before SwiftMutator runs")
    func warmBuildFails() throws {
        var scenario = try FakeMutator.recorded("full")
        scenario.buildStatus = 1
        scenario.buildOutput = "Compiling Lib\n@ROOT@/Sources/Lib/Lib.swift:1:1: error: boom\n"
        let harness = try MutationRunHarness(scenario)
        defer { harness.remove() }

        let run = harness.run()

        #expect(run.status.state == .failed)
        #expect(run.status.reason == "the warm build (`swift build --build-tests`) exited 1: "
            + "Compiling Lib\n<copy>/Sources/Lib/Lib.swift:1:1: error: boom")
        #expect(harness.fake.calls(of: "swift-mutator").isEmpty)
        #expect(FileClone.exists(harness.directory.appendingPathComponent("work")) == false)
        #expect(run.identity == nil && run.status.version == nil)
    }

    @Test("a results path SwiftMutator printed that isn't the one its log folder holds fails the run, naming both")
    func savedPathDisagrees() throws {
        var elsewhere = try FakeMutator.recorded("full")
        elsewhere.log = "💾 Each mutant's result is in @PARENT@/elsewhere/results.jsonl\n"
        var missing = FakeMutator.Scenario()
        missing.log = "💾 SwiftMutator saves each mutant's result as it finishes, in @PARENT@/x/results.jsonl\n"
        let disagreeing = try MutationRunHarness(elsewhere)
        let absent = try MutationRunHarness(missing)
        defer {
            disagreeing.remove()
            absent.remove()
        }

        let run = disagreeing.run()
        let none = absent.run()

        #expect(run.status.state == .failed)
        #expect(run.status.reason == "SwiftMutator named its results file <work>/elsewhere/results.jsonl, but its log "
            + "folder holds <run>/results.jsonl")
        #expect(none.status.reason == "SwiftMutator named its results file <work>/x/results.jsonl, but its log "
            + "folder holds none")
        #expect(MutationCommand.savedPath(in: "a\n💾 Each tested mutant's result is in /p/a in /b.jsonl\nz")
            == "/p/a in /b.jsonl")
    }

    @Test("a report that fails or doesn't read leaves every kill unjudged, with a warning, while the run still ran")
    func reportFails() throws {
        var failing = try FakeMutator.recorded("full")
        failing.reportStatus = 1
        var garbled = try FakeMutator.recorded("full")
        garbled.report = "{"
        let failingHarness = try MutationRunHarness(failing)
        let garbledHarness = try MutationRunHarness(garbled)
        defer {
            failingHarness.remove()
            garbledHarness.remove()
        }

        let failed = failingHarness.run()
        let unread = garbledHarness.run()

        for run in [failed, unread] {
            #expect(run.status.state == .ran)
            #expect(run.suspects == .unjudged)
            #expect(run.resultsFile != nil)
        }
        #expect(failed.warnings.map(\.message)
            == ["swiftmutator: swift-mutator report exited 1; kills only suspect tests made aren't judged"])
        #expect(unread.warnings.map(\.message)
            == ["swiftmutator: swift-mutator report's JSON doesn't read; kills only suspect tests made aren't judged"])
        let kept = try #require(failed.resultsFile)
        let report = failingHarness.package.root.appendingPathComponent(kept)
            .deletingLastPathComponent()
            .appendingPathComponent("report.json")
        #expect(FileClone.exists(report) == false)
        #expect(try failingHarness.scan().warnings.map(\.message).contains(failed.warnings[0].message))
    }

    @Test("""
        kills by a failed test the report has no entry for that reads, its key unreadable or the entry missing, are \
        counted in a warning the scan keeps, and the scan stores them unjudged
        """)
    func unreportedKills() throws {
        var scenario = try FakeMutator.recorded("full")
        let entry = { (key: String) in #""key": "Sources/Core/Bounds.swift:\#(key)""# }
        scenario.report = try #require(scenario.report)
            .replacing(entry("18:5 RelationalOperatorReplacement"), with: entry("18:x RelationalOperatorReplacement"))
            .replacing(entry("18:5 ReplaceBooleanValue"), with: entry("99:5 ReplaceBooleanValue"))
            .replacing(#""suspectsChecked": false"#, with: #""suspectsChecked": true"#)
        #expect(scenario.report?.contains(#""suspectsChecked": true"#) == true)
        let harness = try MutationRunHarness(scenario)
        defer { harness.remove() }

        let run = harness.run()
        let scan = try PackageScanner(describer: harness.package.describer, tools: SnapshotHarness.noTools)
            .scan(packageAt: harness.package.root, tiers: RequestedTiers(mutation: .full))

        let message = "swiftmutator: swift-mutator report's JSON has no entry that reads for 2 kills by a failed "
            + "test, so they aren't judged"
        #expect(run.status.state == .ran && run.suspects.read && run.suspects.unreadableKeys == 1)
        #expect(run.warnings.map(\.message) == [message])
        #expect(scan.warnings.map(\.message).contains(message))
        #expect(MutationSession.describesResults(ScanWarning(file: nil, message: message)))
        let unjudged = try #require(scan.mutation).mutants.filter { mutant in
            mutant.path == "Sources/Core/Bounds.swift" && mutant.line == 18 && mutant.column == 5
        }
        #expect(unjudged.count == 2 && unjudged.allSatisfy { $0.suspectOnly == nil })
        #expect(try #require(scan.mutation).mutants.contains { $0.suspectOnly == JSONFlag(false) })
        #expect(MutationSession.unreportedWarning(1)?.message
            == "swiftmutator: swift-mutator report's JSON has no entry that reads for 1 kill by a failed test, so it "
                + "isn't judged")
        #expect(MutationSession.unreportedWarning(0) == nil)
    }

    @Test("""
        lines of the results file that don't read are warned about when the run ran and its results were kept, \
        never when it failed and nothing of them was kept
        """)
    func skippedLinesOnlyWhenKept() throws {
        let cutOff = #"{"kind":"mutant","sess"#
        var ran = try FakeMutator.recorded("full")
        ran.results = (ran.results ?? "") + cutOff + "\n"
        var interrupted = try FakeMutator.recorded("interrupted")
        interrupted.results = (interrupted.results ?? "") + cutOff + "\n"
        let ranHarness = try MutationRunHarness(ran)
        let failedHarness = try MutationRunHarness(interrupted)
        defer {
            ranHarness.remove()
            failedHarness.remove()
        }

        let kept = ranHarness.run()
        let failed = failedHarness.run()

        let skipped = try #require(kept.warnings.first)
        #expect(kept.status.state == .ran && MutationResults.isSkippedLinesWarning(skipped))
        #expect(skipped.message.hasPrefix("swiftmutator: skipped 1 line of the results file that didn't read ("))
        #expect(failed.status.state == .failed && failed.status.version != nil)
        #expect(failed.warnings.contains(where: MutationResults.isSkippedLinesWarning) == false)
    }

    @Test("""
        the test command's swift is collectors.coverage.path even with coverage disabled; with no swift the run is \
        skipped, --since is skipped without the base a store gives, and a resume with no run pending fails saying so
        """)
    func testSwift() throws {
        let disabledCoverage = try MutationRunHarness(try FakeMutator.recorded("full")) { fake in
            "collectors:\n  coverage:\n    enabled: false\n    path: \(fake.swift.path)\n"
                + "  swiftmutator:\n    path: \(fake.mutator.path)\n"
        }
        let noSwift = try MutationRunHarness(try FakeMutator.recorded("full")) { fake in
            "collectors:\n  swiftmutator:\n    path: \(fake.mutator.path)\n"
        }
        defer {
            disabledCoverage.remove()
            noSwift.remove()
        }

        let ran = try disabledCoverage.scan().status
        let skipped = try noSwift.scan().status
        let since = try disabledCoverage.scan(.since("HEAD~1")).status
        let resume = try disabledCoverage.scan(.resume).status

        #expect(ran?.state == .ran)
        #expect(disabledCoverage.fake.configuration?.hasPrefix("executable: \"\(disabledCoverage.fake.swift.path)\"")
            == true)
        #expect(skipped?.state == .skipped)
        #expect(skipped?.reason == "`swift` not found on PATH; set collectors.coverage.path")
        #expect(since?.state == .skipped)
        #expect(since?.reason == "--since merges with a stored snapshot, and this scan has no store")
        #expect(resume?.state == .failed)
        #expect(resume?.reason == "no interrupted or failed SwiftMutator run to resume")
        #expect(noSwift.fake.calls(of: "swift-mutator").isEmpty)
    }

    @Test("""
        a stored run is identified by the build its results header names, labelled only when the binary is that \
        build; a run that read no header by its binary
        """)
    func snapshotIdentity() throws {
        let ran = try MutationRunHarness(try FakeMutator.recorded("full"))
        let failed = try MutationRunHarness(FakeMutator.Scenario(status: 1))
        defer {
            ran.remove()
            failed.remove()
        }

        let info = { (harness: MutationRunHarness) throws -> CollectorRunInfo? in
            let workspace = try SnapshotWorkspace(
                packageRoot: harness.package.root,
                configurationFile: nil,
                storeOverride: nil,
                build: SnapshotHarness.build,
                describer: harness.package.describer,
                tools: SnapshotHarness.noTools
            )
            let tiers = RequestedTiers(mutation: .full)
            let stored = try workspace.scanWorkingTree(history: .skipped("test"), tiers: tiers)
            return stored.snapshot.info.collectors.first { $0.name == MutationAdapter.name }
        }
        let ranInfo = try #require(try info(ran))
        let failedInfo = try #require(try info(failed))

        #expect(ranInfo.state == .ran)
        #expect(ranInfo.identity == Self.recordedBuild)
        #expect(ranInfo.identityLabel == nil)
        #expect(ranInfo.version == "0.1.0")
        #expect(failedInfo.state == .failed)
        #expect(failedInfo.identity == BinaryIdentity.of(failed.fake.mutator)?.identity)
    }
}

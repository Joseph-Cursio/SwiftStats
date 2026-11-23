import Foundation
@testable import SwiftStatsCore
import Testing

/// How a SwiftMutator run's ending becomes the collector's state (M6,
/// design §1.5), one row of the table at a time, through the fake tools:
/// the state, the whole reason (no paths, the copy as `<copy>`), whether
/// the copy is kept for a resume, and whether results come with it.
@Suite("Mutation exits")
struct MutationExitTests {
    /// One row of the exit table.
    struct Row: Sendable, CustomTestStringConvertible {
        /// What the row is.
        let name: String
        /// What the fake does.
        let scenario: @Sendable () throws -> FakeMutator.Scenario
        /// The collector's state.
        let state: CollectorState
        /// The collector's reason.
        let reason: String
        /// Whether the copy stays for a resume.
        let keepsCopy: Bool
        /// Whether the run gives results.
        let givesResults: Bool

        /// The row's name in the test report.
        var testDescription: String {
            name
        }
    }

    /// SwiftMutator's error when it found no Swift file it could mutate
    /// (`MuterError.noSourceFilesDiscovered` at b16642de).
    static let noSourceFiles = """
        SwiftMutator wasn't able to discover any code it could mutation test.

        This is likely caused by misconfiguring SwiftMutator, usually by excluding a directory that contains your code.
        """
    /// Its error when it found no mutation point
    /// (`MuterError.noMutationPointsDiscovered` at b16642de).
    static let noMutationPoints = """
        SwiftMutator wasn't able to discover any code it could mutation test.

        This is likely caused by misconfiguring SwiftMutator, usually by excluding a directory that contains your \
        code, or by choosing operators that don't apply to it, with --operators, --skip-operators, or the operators \
        and skipOperators keys.
        """

    /// Every row.
    static let rows: [Row] = [
        Row(
            name: "exit 0 without a results file",
            scenario: { FakeMutator.Scenario() },
            state: .failed,
            reason: "swift-mutator exited 0 without a results file",
            keepsCopy: false,
            givesResults: false
        ),
        Row(
            name: "exit 2 with results",
            scenario: { try status(2, of: FakeMutator.recorded("full")) },
            state: .ran,
            reason: "every mutant was a build error",
            keepsCopy: false,
            givesResults: true
        ),
        Row(
            name: "exit 3 with a stopped line",
            scenario: { try FakeMutator.recorded("stopped") },
            state: .failed,
            reason: "the baseline failed (baselineTestFailed); failing: alwaysFails(); "
                + "SwiftMutator needs passing tests; collectors.swiftmutator.arguments can --skip them",
            keepsCopy: false,
            givesResults: false
        ),
        Row(
            name: "exit 4 with results",
            scenario: { try aborted() },
            state: .failed,
            reason: "aborted: tooManyBuildErrors; scan --mutation --resume continues it",
            keepsCopy: true,
            givesResults: false
        ),
        Row(
            name: "exit 5",
            scenario: { logging("Refused to resume @ROOT@'s run", status: 5) },
            state: .failed,
            reason: "swift-mutator exited 5: Refused to resume <copy>'s run",
            keepsCopy: false,
            givesResults: false
        ),
        Row(
            name: "exit 6",
            scenario: { logging("locked", status: 6) },
            state: .failed,
            reason: "another SwiftMutator run holds its lock",
            keepsCopy: false,
            givesResults: false
        ),
        Row(
            name: "exit 7",
            scenario: { logging("test plan refused", status: 7) },
            state: .failed,
            reason: "swift-mutator exited 7: test plan refused",
            keepsCopy: false,
            givesResults: false
        ),
        Row(
            name: "exit 8",
            scenario: { logging("baseline file refused", status: 8) },
            state: .failed,
            reason: "swift-mutator exited 8: baseline file refused",
            keepsCopy: false,
            givesResults: false
        ),
        Row(
            name: "exit 64",
            scenario: { logging("Error: Unknown option '--frobnicate'", status: 64) },
            state: .failed,
            reason: "swift-mutator exited 64: Error: Unknown option '--frobnicate'",
            keepsCopy: false,
            givesResults: false
        ),
        Row(
            name: "exit 255 finding no Swift file to test",
            scenario: { erring(noSourceFiles, status: 255) },
            state: .ran,
            reason: "nothing SwiftMutator could test",
            keepsCopy: false,
            givesResults: false
        ),
        Row(
            name: "exit 255 finding no mutation point",
            scenario: { erring(noMutationPoints, status: 255) },
            state: .ran,
            reason: "nothing SwiftMutator could test",
            keepsCopy: false,
            givesResults: false
        ),
        Row(
            name: "exit 255 on any other error",
            scenario: { logging("Could not read @ROOT@/../muter.conf.yml", status: 255) },
            state: .failed,
            reason: "swift-mutator exited 255: Could not read <copy>/../muter.conf.yml",
            keepsCopy: false,
            givesResults: false
        ),
        Row(
            name: "SIGTERM after testing some mutants",
            scenario: { try FakeMutator.recorded("interrupted") },
            state: .failed,
            reason: "interrupted by SIGTERM; scan --mutation --resume continues it",
            keepsCopy: true,
            givesResults: false
        ),
        Row(
            name: "exit 143 after testing some mutants",
            scenario: { try exiting143() },
            state: .failed,
            reason: "interrupted by SIGTERM; scan --mutation --resume continues it",
            keepsCopy: true,
            givesResults: false
        ),
        Row(
            name: "SIGINT before any results",
            scenario: { interrupting() },
            state: .failed,
            reason: "interrupted by SIGINT",
            keepsCopy: false,
            givesResults: false
        ),
        Row(
            name: "any other exit",
            scenario: { logging("boom", status: 1) },
            state: .failed,
            reason: "swift-mutator exited 1: boom",
            keepsCopy: false,
            givesResults: false
        ),
        Row(
            name: "exit 0 with a results file in a newer format",
            scenario: { try newerFormat() },
            state: .failed,
            reason: "the results file has formatVersion 5; this SwiftStats reads 1 to 4",
            keepsCopy: false,
            givesResults: false
        )
    ]

    /// `scenario` exiting `status`.
    private static func status(_ status: Int32, of scenario: FakeMutator.Scenario) -> FakeMutator.Scenario {
        var changed = scenario
        changed.status = status
        return changed
    }

    /// A run that prints `log` and exits `status`, leaving no results.
    private static func logging(_ log: String, status: Int32) -> FakeMutator.Scenario {
        FakeMutator.Scenario(log: log + "\n", status: status)
    }

    /// A run that prints `error` on standard error and exits `status`.
    private static func erring(_ error: String, status: Int32) -> FakeMutator.Scenario {
        FakeMutator.Scenario(errorText: error + "\n", status: status)
    }

    /// The interrupted recording, aborted mid-run instead (exit 4, an end
    /// line `aborted` with detail `tooManyBuildErrors`).
    private static func aborted() throws -> FakeMutator.Scenario {
        var scenario = try FakeMutator.recorded("interrupted")
        scenario.results = scenario.results?
            .replacingOccurrences(of: "\"detail\":\"SIGTERM\"", with: "\"detail\":\"tooManyBuildErrors\"")
            .replacingOccurrences(of: "\"reason\":\"interrupted\"", with: "\"reason\":\"aborted\"")
        scenario.signal = nil
        scenario.status = 4
        return scenario
    }

    /// The interrupted recording, ending by SIGTERM's fallback exit, 143.
    private static func exiting143() throws -> FakeMutator.Scenario {
        var scenario = try FakeMutator.recorded("interrupted")
        scenario.signal = nil
        scenario.status = 143
        return scenario
    }

    /// A run SIGINT ends before it writes a results file.
    private static func interrupting() -> FakeMutator.Scenario {
        var scenario = FakeMutator.Scenario()
        scenario.signal = SIGINT
        return scenario
    }

    /// The full recording with its header in format 5.
    private static func newerFormat() throws -> FakeMutator.Scenario {
        var scenario = try FakeMutator.recorded("full")
        scenario.results = scenario.results?
            .replacingOccurrences(of: "\"formatVersion\":4", with: "\"formatVersion\":5")
        return scenario
    }

    @Test("each way a SwiftMutator run can end gives its state, its reason and its copy's fate", arguments: rows)
    func exitTable(_ row: Row) throws {
        let harness = try MutationRunHarness(try row.scenario())
        defer { harness.remove() }

        let run = harness.run()

        #expect(run.status.state == row.state)
        #expect(run.status.reason == row.reason)
        #expect(FileClone.exists(harness.directory.appendingPathComponent("work")) == row.keepsCopy)
        #expect((run.results != nil) == row.givesResults)
        #expect((run.resultsFile != nil) == row.givesResults)
        #expect(run.warmBuildMilliseconds != nil)
    }

    @Test("signals are named in reasons, and only SIGHUP, SIGINT and SIGTERM read from an exit of 128 plus n")
    func signals() {
        let results = MutationExit.Output.noFile
        let fallback = MutationExit.judge(.exited(130), output: results, log: "", tail: "", since: false)
        let crash = MutationExit.judge(.exited(139), output: results, log: "", tail: "", since: false)
        let killed = MutationExit.judge(.signalled(SIGKILL), output: results, log: "", tail: "", since: false)

        #expect(fallback.reason == "interrupted by SIGINT")
        #expect(crash.reason == "swift-mutator exited 139")
        #expect(killed.reason == "interrupted by SIGKILL")
        #expect(MutationExit.signalName(SIGHUP) == "SIGHUP")
        #expect(MutationExit.signalName(30) == "signal 30")
    }
}

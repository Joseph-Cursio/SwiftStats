import Foundation
@testable import SwiftStatsCore
import Testing

/// How `ProcessRunner` says a command ended (M6, design §1.5): by its exit
/// status, or by a signal it didn't handle, which SwiftMutator raises again
/// to end an interrupted run; and its logged run, which appends both
/// output streams to a file and gives the command an empty standard input.
@Suite("Process termination")
struct ProcessTerminationTests {
    @Test("a command a signal ends reads as signalled, and one that exits 143 as exited")
    func reasons() throws {
        let directory = FileManager.default.temporaryDirectory
        let shell = "/bin/sh"

        let signalled = try ProcessRunner.runToEnd(executable: shell, arguments: ["-c", "kill -TERM $$"], in: directory)
        let exited = try ProcessRunner.runToEnd(executable: shell, arguments: ["-c", "exit 143"], in: directory)

        #expect(signalled.termination == .signalled(SIGTERM))
        #expect(exited.termination == .exited(143))
        #expect(exited.status == 143)
    }

    @Test("a logged run appends standard output and standard error to the log, with nothing on standard input")
    func loggedRun() throws {
        let directory = try SnapshotHarness.temporaryDirectory("LoggedRun")
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent("run.log")
        try "before\n".write(to: log, atomically: true, encoding: .utf8)

        let termination = try ProcessRunner.runLogged(
            executable: "/bin/sh",
            arguments: [
                "-c", "echo out; echo err >&2; if read -r line; then echo input; else echo \"$COLOR\"; fi; exit 3"
            ],
            in: directory,
            environment: ProcessEnvironment(added: ["COLOR": "none"], removed: []),
            logging: LoggedRun(log: log, stop: .standard)
        )

        #expect(termination == .exited(3))
        #expect(try String(contentsOf: log, encoding: .utf8) == "before\nout\nerr\nnone\n")
    }
}

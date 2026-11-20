import ArgumentParser
import SwiftStatsCore

/// Entry point for the `swiftstats` command-line tool.
///
/// `scan` arrived in M0, `report` and `diff` in M2; `trend`, `top` and
/// `backfill` follow with later milestones in the PRD.
@main
struct SwiftStatsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftstats",
        abstract: "Per-function statistics and trends for Swift packages.",
        version: SwiftStatsVersion.current,
        subcommands: [
            ScanCommand.self,
            ReportCommand.self,
            DiffCommand.self,
            TopCommand.self,
            TrendCommand.self,
            BackfillCommand.self
        ]
    )

    /// Runs the command, cleaning up if a signal interrupts it.
    static func main() {
        InterruptCleanup.install()
        main(nil)
    }
}

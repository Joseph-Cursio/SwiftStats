import ArgumentParser
import SwiftStatsCore

/// Entry point for the `swiftstats` command-line tool.
///
/// `scan` arrives in M0; `report`, `diff`, `trend`, `top` and `backfill`
/// follow with later milestones in the PRD.
@main
struct SwiftStatsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftstats",
        abstract: "Per-function statistics and trends for Swift packages.",
        version: SwiftStatsVersion.current,
        subcommands: [ScanCommand.self]
    )
}

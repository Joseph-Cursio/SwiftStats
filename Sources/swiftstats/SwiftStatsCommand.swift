import ArgumentParser
import SwiftStatsCore

/// Entry point for the `swiftstats` command-line tool.
///
/// Subcommands (`scan`, `report`, `diff`, `trend`, `top`, `backfill`) arrive
/// with the milestones in the PRD; until then this only reports its version.
@main
struct SwiftStatsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftstats",
        abstract: "Per-function statistics and trends for Swift packages.",
        version: SwiftStatsVersion.current
    )
}

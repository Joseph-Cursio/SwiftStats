import ArgumentParser
import Foundation
import SwiftStatsCore

/// `swiftstats diff`: what changed between two snapshots.
struct DiffCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diff",
        abstract: "Show what changed between two commits' snapshots.",
        discussion: """
        Compares functions (added, removed, moved, renamed, changed) and metrics, for collectors that ran \
        in both snapshots with the same build and options. A commit with no snapshot is scanned first, \
        from a copy of its tracked files checked out into a temporary directory, and stored. A rescan keeps \
        the coverage of the snapshot it replaces when the tree, the records and the mapping rule are the same, \
        and otherwise stops; --drop-coverage replaces it without its coverage instead.
        """
    )

    @Argument(help: "The older commit, branch or tag.")
    var older: String

    @Argument(help: "The newer commit, branch or tag (default: HEAD).")
    var newer: String?

    @Option(help: "The package directory (the one containing Package.swift).")
    var package = "."

    @Option(help: "Output format.")
    var format: ReportFormat = .markdown

    @Option(name: .shortAndLong, help: "Write the diff to this file instead of standard output.")
    var output: String?

    @Flag(help: "Compare with the working tree's uncommitted changes when no newer commit is given.")
    var includeDirty = false

    @Flag(help: "Rescan both commits with this build first.")
    var rescan = false

    @Flag(help: "Replace a snapshot holding coverage a rescan can't keep, dropping the coverage.")
    var dropCoverage = false

    @OptionGroup var options: PackageOptions

    func run() throws {
        try CommandFailure.reporting {
            let workspace = try options.workspace(path: package)
            let ids = try workspace.diffSnapshotIDs(
                older: older,
                newer: newer,
                includeDirty: includeDirty,
                rescan: rescan,
                dropCoverage: dropCoverage
            )
            let store = workspace.store
            let diff = SnapshotDiff.diff(try store.load(id: ids.older), try store.load(id: ids.newer))
            let data: Data = switch format {
            case .json:
                try ScanReportEncoder.encode(diff)

            case .markdown:
                Data(MarkdownDiff.render(diff).utf8)
            }
            try CommandFailure.write(data, to: output)
        }
    }
}

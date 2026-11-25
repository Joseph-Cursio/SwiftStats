import ArgumentParser
import Foundation
import SwiftStatsCore

/// `swiftstats report`: a stored snapshot with its roll-ups.
struct ReportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Show a stored snapshot.",
        discussion: """
        Shows the working tree's snapshot (HEAD's, or its uncommitted one when the tree has changes and one \
        was scanned), or --commit's. Outside git, the latest. Run `swiftstats scan` first. The signals are \
        computed when the report is made, with the thresholds under `signals:` in this package's configuration \
        (the mutation and hidden-coupling limits included); each signal's rule states those it used, and the \
        JSON lists them under `thresholds`. The Build and index and the Dead code sections and the three index \
        signals hold results only for a snapshot scanned with --index, or keeping the results of such a scan of \
        the same tree, and otherwise say how to collect them; the change-coupling pairs are read from the \
        store's table.
        """
    )

    @Argument(help: "The package directory (the one containing Package.swift).")
    var path = "."

    @Option(help: "Show this commit's snapshot instead of the working tree's.")
    var commit: String?

    @Option(help: "Output format.")
    var format: ReportFormat = .markdown

    @Option(name: .shortAndLong, help: "Write the report to this file instead of standard output.")
    var output: String?

    @OptionGroup var options: PackageOptions

    func run() throws {
        try CommandFailure.reporting {
            let workspace = try options.workspace(path: path)
            let id = try workspace.reportSnapshotID(revision: commit)
            let report = SnapshotReport(
                snapshot: try workspace.store.info(id: id),
                signals: try workspace.signals(id: id),
                thresholds: workspace.configuration.signals,
                scan: try workspace.store.report(id: id)
            )
            let data: Data = switch format {
            case .json:
                try ScanReportEncoder.encode(report)

            case .markdown:
                Data(MarkdownReport.render(report).utf8)
            }
            try CommandFailure.write(data, to: output)
        }
    }
}

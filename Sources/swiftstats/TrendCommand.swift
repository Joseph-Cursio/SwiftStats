//
//  TrendCommand.swift
//  swiftstats
//
//  `swiftstats trend <metric>` (PRD §10): a roll-up number over time.
//

import ArgumentParser
import Foundation
import SwiftStatsCore

/// `swiftstats trend`: a metric over HEAD's first-parent commits.
struct TrendCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trend",
        abstract: "Show a roll-up number over HEAD's first-parent commits.",
        discussion: """
        The metric is a roll-up number's path, such as fileLength.total, cognitive.median or \
        findings.swiftlint.line_length. Points come from stored clean snapshots; `swiftstats backfill` \
        adds past commits. A break marks a point whose collector or SwiftStats build differs from the one before.
        """
    )

    @Argument(help: "The roll-up number's path.")
    var metric: String

    @Option(help: "The package directory (the one containing Package.swift).")
    var package = "."

    @Option(help: "Follow this module instead of a project part.")
    var module: String?

    @Option(help: "The project part to follow.")
    var part: ProjectPart = .production

    @Option(help: "Output format.")
    var format: ReportFormat = .markdown

    @Option(name: .shortAndLong, help: "Write the trend to this file instead of standard output.")
    var output: String?

    @OptionGroup var options: PackageOptions

    func run() throws {
        try CommandFailure.reporting {
            let workspace = try options.workspace(path: package)
            let report = try workspace.trend(
                metric: metric,
                scope: module == nil ? .project : .module,
                name: module ?? part.rawValue
            )
            let data: Data = switch format {
            case .json:
                try ScanReportEncoder.encode(report)

            case .markdown:
                Data(MarkdownTrend.render(report).utf8)
            }
            try CommandFailure.write(data, to: output)
        }
    }
}

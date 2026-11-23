//
//  TopCommand.swift
//  swiftstats
//
//  `swiftstats top <signal>` (PRD §10): a derived signal's ranking for the
//  same snapshot `report` would show.
//

import ArgumentParser
import Foundation
import SwiftStatsCore

/// `swiftstats top`: one signal's ranked functions.
struct TopCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "top",
        abstract: "List a derived signal's functions, highest score first.",
        discussion: """
        A ranked signal (hotspot, bug-prone, clone-hotspot) lists every candidate with a score above zero \
        and marks its members; the others list only their members, highest score first, so `top` adds the \
        ranking. Signals: \(SignalName.reportOrder.map(\.rawValue).joined(separator: ", ")). The snapshot is \
        the one `report` would show; thresholds and the mutation signals' limits come from `signals:` in this \
        package's configuration.
        """
    )

    @Argument(help: "The signal.")
    var signal: SignalName

    @Option(help: "The package directory (the one containing Package.swift).")
    var package = "."

    @Option(help: "Use this commit's snapshot instead of the working tree's.")
    var commit: String?

    @Option(help: "How many functions to list.")
    var limit = MarkdownSignals.defaultTopLimit

    @Option(help: "Output format.")
    var format: ReportFormat = .markdown

    @Option(name: .shortAndLong, help: "Write the list to this file instead of standard output.")
    var output: String?

    @OptionGroup var options: PackageOptions

    func validate() throws {
        guard limit > 0 else {
            throw ValidationError("--limit must be at least 1")
        }
    }

    func run() throws {
        try CommandFailure.reporting {
            let workspace = try options.workspace(path: package)
            let id = try workspace.reportSnapshotID(revision: commit)
            guard let result = try workspace.signals(id: id).first(where: { $0.name == signal }) else {
                return
            }
            let data: Data = switch format {
            case .json:
                try ScanReportEncoder.encode(
                    TopReport(snapshot: try workspace.store.info(id: id), signal: result, limit: limit)
                )

            case .markdown:
                Data(MarkdownSignals.top(result, limit: limit).utf8)
            }
            try CommandFailure.write(data, to: output)
        }
    }
}

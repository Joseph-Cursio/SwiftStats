import ArgumentParser
import Foundation
import SwiftStatsCore

/// `swiftstats scan`: the syntax-only (T0) scan of a package.
struct ScanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Scan a SwiftPM package and print its function records as JSON."
    )

    @Argument(help: "The package directory (the one containing Package.swift).")
    var path = "."

    @Option(help: "Output format. Only json exists in M0.")
    var format: ScanFormat = .json

    @Option(name: .shortAndLong, help: "Write the report to this file instead of standard output.")
    var output: String?

    func run() throws {
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let report: ScanReport
        do {
            report = try PackageScanner().scan(packageAt: root)
        } catch let error as ScanError {
            throw ValidationError(error.description)
        }
        let data = try ScanReportEncoder.encode(report)
        if let output {
            try data.write(to: URL(fileURLWithPath: output))
        } else {
            FileHandle.standardOutput.write(data)
        }
    }
}

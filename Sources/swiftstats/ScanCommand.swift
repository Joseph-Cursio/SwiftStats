import ArgumentParser
import Foundation
import SwiftStatsCore

/// `swiftstats scan`: the syntax-only (T0) scan of a package.
struct ScanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Scan a SwiftPM package and print its records, findings, test inventory, "
            + "dependencies, roll-ups and Sitrep-compatible counts as JSON.",
        discussion: """
        SwiftProjectLint and SwiftLint run when found on PATH (as swiftprojectlint and swiftlint), \
        or at collectors.<name>.path in .swiftstats.yml; collectors.<name>.enabled: false turns one off. \
        The dependency graph comes from `swift package show-dependencies`, run only when the package's \
        dependencies are already resolved.
        """
    )

    @Argument(help: "The package directory (the one containing Package.swift).")
    var path = "."

    @Option(help: "Output format. Only json exists so far.")
    var format: ScanFormat = .json

    @Option(name: .shortAndLong, help: "Write the report to this file instead of standard output.")
    var output: String?

    @Option(help: "Read this configuration file instead of the package's .swiftstats.yml.")
    var config: String?

    func run() throws {
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let report: ScanReport
        do {
            if let config {
                report = try PackageScanner().scan(packageAt: root, configurationFile: URL(fileURLWithPath: config))
            } else {
                report = try PackageScanner().scan(packageAt: root)
            }
        } catch ScanError.notAPackage(let path) {
            // A wrong path is a usage error: exit 64 with the usage text.
            throw ValidationError(ScanError.notAPackage(path).description)
        } catch let error as ScanError {
            // Anything else went wrong in the environment, not on the command
            // line: report it and exit 1 without the usage text.
            FileHandle.standardError.write(Data("Error: \(error.description)\n".utf8))
            throw ExitCode.failure
        }
        let data = try ScanReportEncoder.encode(report)
        if let output {
            try data.write(to: URL(fileURLWithPath: output))
        } else {
            FileHandle.standardOutput.write(data)
        }
    }
}

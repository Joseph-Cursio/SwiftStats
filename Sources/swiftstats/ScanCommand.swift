import ArgumentParser
import Foundation
import SwiftStatsCore

/// `swiftstats scan`: the syntax-only (T0) scan of a package, stored as a snapshot.
struct ScanCommand: ParsableCommand {
    /// How many characters of a commit the summary shows.
    private static let shortCommitLength = 10

    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Scan a SwiftPM package and store the snapshot.",
        discussion: """
        The snapshot goes to the package's store (.swiftstats/stats.sqlite, or store: in .swiftstats.yml, \
        or --store), replacing any earlier snapshot of the same commit and dirtiness. --format json prints \
        the scan's records, findings, test inventory, dependencies, roll-ups and Sitrep-compatible counts; \
        -o writes them to a file. SwiftProjectLint and SwiftLint run when found on PATH (as swiftprojectlint \
        and swiftlint), or at collectors.<name>.path in .swiftstats.yml; collectors.<name>.enabled: false \
        turns one off. Side effects come from the linked SwiftEffectInference \
        (collectors.swifteffectinference.enabled: false turns it off). The dependency graph comes from \
        `swift package show-dependencies`, run only when the package's dependencies are already resolved.
        """
    )

    @Argument(help: "The package directory (the one containing Package.swift).")
    var path = "."

    @Option(help: "Print the scan in this format.")
    var format: ScanFormat?

    @Option(name: .shortAndLong, help: "Write the scan JSON to this file.")
    var output: String?

    @Flag(help: "Don't store the snapshot; print the scan JSON instead. Reads no git history.")
    var noStore = false

    @Flag(help: "Don't read the git history (churn, fixes and the signals built on them).")
    var noHistory = false

    @OptionGroup var options: PackageOptions

    func run() throws {
        try CommandFailure.reporting {
            let report: ScanReport
            if noStore {
                let root = URL(fileURLWithPath: path, isDirectory: true)
                report = try options.config.map { file in
                    try PackageScanner().scan(packageAt: root, configurationFile: URL(fileURLWithPath: file))
                } ?? PackageScanner().scan(packageAt: root)
            } else {
                let workspace = try options.workspace(path: path)
                let history: HistorySource = noHistory ? .skipped("--no-history") : .automatic
                let (snapshot, _) = try workspace.scanWorkingTree(history: history)
                report = snapshot.report
                FileHandle.standardError.write(Data((summary(snapshot.info, store: workspace.store.url) + "\n").utf8))
            }
            if output != nil || format != nil || noStore {
                try CommandFailure.write(try ScanReportEncoder.encode(report), to: output)
            }
        }
    }

    /// The line `scan` prints about the snapshot it stored.
    private func summary(_ info: SnapshotInfo, store: URL) -> String {
        let commit = info.git.commit.map { String($0.prefix(Self.shortCommitLength)) } ?? "the working tree (no git)"
        let dirty = info.git.isDirty ? " with uncommitted changes" : ""
        return "Stored a snapshot of \(info.package) at \(commit)\(dirty) in \(store.path)"
    }
}

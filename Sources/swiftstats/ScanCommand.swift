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
        the scan's records, findings, test inventory, dependencies, law checks, property-test suggestions, \
        clones, roll-ups and Sitrep-compatible counts; -o writes them to a file. SwiftProjectLint, SwiftLint, \
        SwiftInferProperties and SwiftCloneDetector run when found on PATH (as swiftprojectlint, swiftlint, \
        swift-infer and swift-clone-detector), or at collectors.<name>.path in .swiftstats.yml; \
        collectors.<name>.enabled: false turns one off. Side effects come from the linked SwiftEffectInference \
        (collectors.swifteffectinference.enabled: false turns it off). The dependency graph comes from \
        `swift package show-dependencies`, run only when the package's dependencies are already resolved. \
        --coverage also builds and runs the package's tests with code coverage, in .swiftstats/coverage-build, \
        with the toolchain of the swift on PATH or at collectors.coverage.path; collectors.coverage.arguments \
        may add --skip <regex> pairs to swift test. A scan without --coverage, or whose coverage run fails, keeps \
        the coverage of the snapshot it replaces when the tree, the records and the mapping rule are the same, \
        and otherwise stops without storing anything; --drop-coverage replaces the snapshot without its coverage \
        instead. --mutation also runs SwiftMutator (swift-mutator on PATH, or collectors.swiftmutator.path) after \
        every other collector, in a temporary copy under .swiftstats/mutation; collectors.swiftmutator.arguments \
        may add --skip <regex> pairs to its test command, and collectors.swiftmutator.options sets workers and \
        timeout; its test command is the swift the coverage collector uses, and its output goes to \
        .swiftstats/mutation/swift-mutator.log. --since <rev> retests only the files changed since that commit's \
        snapshot and keeps its results for the rest; --resume continues an interrupted or failed run in its \
        kept copy while the tree and settings are those it started with, and a scan --mutation without it \
        discards that run. A scan without --mutation, or whose mutation run fails, keeps the mutation results \
        of the snapshot it replaces when the tree, the records they name, the files they test and the mapping \
        rule are the same, and otherwise stops without storing anything; --drop-mutation replaces the snapshot \
        without them instead. A coverage or mutation run asked for that fails or is skipped doesn't fail the scan, \
        which says so on standard error.
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

    @Flag(help: "Also build and run the package's tests with code coverage (minutes on a real package).")
    var coverage = false

    @Flag(help: "Replace a snapshot holding coverage this scan can't keep or can't read, dropping the coverage.")
    var dropCoverage = false

    @Flag(help: "Also run SwiftMutator on the package's tests (most of an hour on a real package).")
    var mutation = false

    @Option(help: "With --mutation, retest only the files changed since this commit's snapshot, keeping the rest.")
    var since: String?

    @Flag(help: "With --mutation, continue the SwiftMutator run an earlier scan left interrupted or failed.")
    var resume = false

    @Flag(help: "Replace a snapshot holding mutation results this scan can't keep or can't read, dropping them.")
    var dropMutation = false

    @OptionGroup var options: PackageOptions

    /// The opt-in collectors the flags ask for.
    private var tiers: RequestedTiers {
        get throws(RequestedTiers.FlagConflict) {
            try RequestedTiers.scanFlags(
                coverage: coverage,
                mutation: mutation,
                since: since,
                resume: resume,
                storing: noStore == false
            )
        }
    }

    func validate() throws {
        do {
            _ = try tiers
        } catch {
            throw ValidationError(error.description)
        }
    }

    func run() throws {
        let requested = try tiers
        let started = Date()
        defer {
            // Named only when this scan's mutation step wrote it, whether
            // or not the scan then stored a snapshot.
            let root = URL(fileURLWithPath: path, isDirectory: true)
            if requested.mutation != nil,
               let log = StoreLocation.mutationLog(packageRoot: root, writtenSince: started) {
                FileHandle.standardError.write(Data("SwiftMutator's output is in \(log.path)\n".utf8))
            }
        }
        try CommandFailure.reporting {
            let report: ScanReport
            if noStore {
                let root = URL(fileURLWithPath: path, isDirectory: true)
                report = try options.config.map { file in
                    try PackageScanner().scan(
                        packageAt: root,
                        configurationFile: URL(fileURLWithPath: file),
                        tiers: requested
                    )
                } ?? PackageScanner().scan(packageAt: root, tiers: requested)
            } else {
                let workspace = try options.workspace(path: path)
                let history: HistorySource = noHistory ? .skipped("--no-history") : .automatic
                let (snapshot, _) = try workspace.scanWorkingTree(
                    history: history,
                    tiers: requested,
                    drop: DropOptions(coverage: dropCoverage, mutation: dropMutation)
                )
                report = snapshot.report
                FileHandle.standardError.write(Data((summary(snapshot.info, store: workspace.store.url) + "\n").utf8))
            }
            // A run asked for that collected nothing doesn't fail the
            // scan, as a failed coverage run never has, but says so.
            for line in UnrunNotice.lines(for: report, requested: requested) {
                FileHandle.standardError.write(Data((line + "\n").utf8))
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

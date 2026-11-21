//
//  BackfillCommand.swift
//  swiftstats
//
//  `swiftstats backfill` (PRD §7.13, §10): snapshots of past first-parent
//  commits, so `trend` has points from the start.
//

import ArgumentParser
import Foundation
import SwiftStatsCore

/// `swiftstats backfill`: scan past commits.
struct BackfillCommand: ParsableCommand {
    /// Characters of a commit hash the progress lines show.
    private static let shortCommitLength = 10

    static let configuration = CommandConfiguration(
        commandName: "backfill",
        abstract: "Scan past commits on HEAD's first-parent line, so trends start with history.",
        discussion: """
        Picks every Nth commit counting from the first (--every), or each week's latest commit in UTC \
        (--weekly, the default). Each is exported without touching the repository and scanned with \
        SwiftStats' own measurements and side effects; --with-tools adds SwiftLint, SwiftProjectLint, \
        SwiftInferProperties and SwiftCloneDetector; git history is never read, nor coverage collected. A \
        commit that already has a snapshot is skipped; --rerun rescans those taken by another SwiftStats build, \
        except snapshots holding history, coverage or tool results a backfill wouldn't collect.
        """
    )

    @Argument(help: "The package directory (the one containing Package.swift).")
    var path = "."

    @Option(help: "Pick every Nth first-parent commit, counting from the first.")
    var every: Int?

    @Flag(help: "Pick each ISO week's latest commit (the default).")
    var weekly = false

    @Option(help: "Only commits from this date (YYYY-MM-DD, UTC) or commit on.")
    var since: String?

    @Option(help: "Scan at most this many picks, the newest.")
    var maxCommits: Int?

    @Flag(help: "Rescan picks whose snapshot came from another SwiftStats build.")
    var rerun = false

    @Flag(help: "Also run SwiftLint, SwiftProjectLint, SwiftInferProperties and SwiftCloneDetector (slow).")
    var withTools = false

    @OptionGroup var options: PackageOptions

    /// The time `value` names: a UTC date, or a commit's committer time.
    private static func time(of value: String, in workspace: SnapshotWorkspace) throws -> Int {
        let format = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day()
        if let date = try? format.parse(value) {
            return Int(date.timeIntervalSince1970)
        }
        guard let time = workspace.committerTime(of: value) else {
            throw ValidationError("--since must be a date (YYYY-MM-DD) or a commit")
        }
        return time
    }

    func validate() throws {
        if let every, every < 1 {
            throw ValidationError("--every must be at least 1")
        }
        if every != nil, weekly {
            throw ValidationError("give --every or --weekly, not both")
        }
        if let maxCommits, maxCommits < 1 {
            throw ValidationError("--max-commits must be at least 1")
        }
    }

    func run() throws {
        try CommandFailure.reporting {
            let workspace = try options.workspace(path: path)
            let plan = BackfillPlan(
                selection: every.map(BackfillSelection.every) ?? .weekly,
                since: try since.map { try Self.time(of: $0, in: workspace) },
                maximumCommits: maxCommits,
                rerun: rerun,
                withTools: withTools
            )
            let steps = try workspace.backfill(plan) { step in
                let note = step.note.map { ": \($0)" } ?? ""
                let commit = step.commit.prefix(Self.shortCommitLength)
                FileHandle.standardError.write(Data("\(commit) \(step.action.rawValue)\(note)\n".utf8))
            }
            let counts = Dictionary(grouping: steps, by: \.action).mapValues(\.count)
            let summary = [BackfillStep.Action.scanned, .skipped, .kept, .failed]
                .map { "\(counts[$0] ?? 0) \($0.rawValue)" }
                .joined(separator: ", ")
            FileHandle.standardError.write(Data("Backfill of \(steps.count) commits: \(summary).\n".utf8))
        }
    }
}

//
//  SnapshotWorkspace+Trend.swift
//  SwiftStatsCore
//
//  `trend` (PRD §10): a roll-up number over the clean snapshots of HEAD's
//  first-parent commits, the same line `backfill` fills in. Snapshots of
//  commits only reachable through a merged branch are counted, not shown.
//

import Foundation

extension SnapshotWorkspace {
    /// The fields of a `%H %ct` log line: commit and committer time.
    private static let logFieldCount = 2

    /// Why `new`'s numbers don't compare with `old`'s for the collectors
    /// in `watching`; nil when they do. A collector that ran on neither side
    /// gave neither a number, so nothing differs and nothing breaks.
    static func breakReason(from old: SnapshotInfo, to new: SnapshotInfo, watching: [String]) -> String? {
        let ranOld = Set(old.collectors.filter { $0.state == .ran }.map(\.name))
        let ranNew = Set(new.collectors.filter { $0.state == .ran }.map(\.name))
        let comparisons = Comparability.compare(old, new).filter { comparison in
            switch comparison.outcome {
            case .compared:
                false

            case .notComparable:
                watching.contains(comparison.name)

            case .notCollected:
                watching.contains(comparison.name)
                    && ranOld.contains(comparison.name) != ranNew.contains(comparison.name)
            }
        }
        let reasons = comparisons.map { comparison in
            "\(comparison.name): \(comparison.reason ?? comparison.outcome.rawValue)"
        }
        return reasons.isEmpty ? nil : reasons.joined(separator: "; ")
    }

    /// HEAD's first-parent commits with their committer dates, oldest first.
    func firstParentLine() throws -> [(commit: String, time: Int)] {
        try firstParentLine(of: "HEAD")
    }

    /// The first-parent commits leading to `revision`, it included, with
    /// their committer dates, oldest first.
    func firstParentLine(of revision: String) throws -> [(commit: String, time: Int)] {
        let data = try ProcessRunner.run(
            executable: GitReader.git,
            arguments: [
                "--no-optional-locks", "-c", "log.showSignature=false", "log", "--first-parent",
                "--no-show-signature", "--no-color", "--format=%H %ct", revision, "--"
            ],
            in: root
        )
        let log = String(bytes: data, encoding: .utf8) ?? ""
        let entries: [(commit: String, time: Int)] = log.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ")
            guard parts.count == Self.logFieldCount, let time = Int(parts[1]) else {
                return nil
            }
            return (String(parts[0]), time)
        }
        return entries.reversed()
    }

    /// Every commit reachable from HEAD.
    func reachableCommits() throws -> Set<String> {
        let data = try ProcessRunner.run(
            executable: GitReader.git,
            arguments: ["--no-optional-locks", "rev-list", "HEAD"],
            in: root
        )
        return Set((String(bytes: data, encoding: .utf8) ?? "").split(separator: "\n").map(String.init))
    }

    /// The trend of roll-up number `metric` in the roll-up `name` of `scope`.
    public func trend(metric: String, scope: RollupScope, name: String) throws -> TrendReport {
        let package = try describer.describePackage(at: root).name
        let git = GitReader.read(packageRoot: root, ignoring: storeInPackage)
        guard git.commit != nil else {
            throw StoreError.noSnapshot("\(package): a trend follows git history, and this package has none")
        }
        let line = try firstParentLine()
        let snapshots = Dictionary(
            try store.cleanSnapshots(package: package, packagePath: git.packagePath).map { ($0.commit, $0.id) }
        ) { _, last in last }
        let collector = RollupMetrics.collector(of: metric.split(separator: ".").map(String.init))
        let watched = Array(Set([SwiftStatsCollector.name, collector])).sorted()
        var points: [TrendPoint] = []
        var previous: SnapshotInfo?
        for (commit, time) in line {
            guard let id = snapshots[commit] else {
                continue
            }
            let info = try store.info(id: id)
            points.append(TrendPoint(
                commit: commit,
                date: HistoryCollector.date(time),
                value: try store.rollupValue(id: id, scope: scope, name: name, metric: metric),
                breakReason: previous.flatMap { Self.breakReason(from: $0, to: info, watching: watched) }
            ))
            previous = info
        }
        let onLine = Set(line.map(\.commit))
        let reachable = try reachableCommits()
        return TrendReport(
            schemaVersion: TrendReport.currentSchemaVersion,
            package: package,
            metric: metric,
            scope: scope,
            name: name,
            points: points,
            offLine: snapshots.keys.filter { reachable.contains($0) && onLine.contains($0) == false }.count
        )
    }
}

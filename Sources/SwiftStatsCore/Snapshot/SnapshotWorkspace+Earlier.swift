//
//  SnapshotWorkspace+Earlier.swift
//  SwiftStatsCore
//
//  The inputs of a report's signals (PRD §8): the snapshot, and for
//  divergent clones an earlier snapshot S with what git says changed
//  since. S is a clean snapshot of a commit before the snapshot's on that
//  commit's first-parent line, where SwiftCloneDetector ran: the latest
//  whose committer date is at or before the start of the history window,
//  else the earliest, so the period compared is a window long when it
//  can be. Git's failure is recorded, not thrown, so it leaves out only
//  the signal needing it.
//

import Foundation

extension SnapshotWorkspace {
    /// `reason`, with what git said when `error` holds it.
    private static func failure(_ reason: String, _ error: any Error) -> String {
        guard case let ScanError.commandFailed(_, _, message) = error else {
            return reason
        }
        let said = message.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return said.isEmpty ? reason : "\(reason): \(said)"
    }

    /// The inputs of `snapshot`'s signals.
    func signalInputs(for snapshot: StoredSnapshot) throws -> SignalInputs {
        guard let history = snapshot.history else {
            return SignalInputs(snapshot: snapshot)
        }
        let commit = history.commitHash
        let line: [(commit: String, time: Int)]
        do {
            line = try firstParentLine(of: commit).filter { $0.commit != commit }
        } catch {
            let reason = "git could not read the first-parent line of \(commit.prefix(MarkdownSignals.shortLength))"
            return SignalInputs(snapshot: snapshot, gitFailure: Self.failure(reason, error))
        }
        let candidates = try cloneSnapshots(on: line, package: snapshot.info)
        let inWindow = candidates.last { HistoryCollector.date($0.time) <= history.windowStart }
        guard let chosen = inWindow ?? candidates.first else {
            return SignalInputs(snapshot: snapshot, earlierNote: DivergentClones.noEarlier)
        }
        let date = HistoryCollector.date(chosen.time)
        var note = "\(chosen.commit.prefix(MarkdownSignals.shortLength)) of \(date.prefix(MarkdownSignals.shortLength))"
        if inWindow == nil {
            note += ", the earliest snapshot with clone data, so the period is shorter than the "
                + "\(history.windowDays)-day window"
        }
        let earlier = try store.load(id: chosen.id)
        do {
            return SignalInputs(
                snapshot: snapshot,
                earlier: earlier,
                earlierNote: note,
                since: try GitChanges.commits(from: chosen.commit, to: commit, in: root),
                hunks: try GitChanges.hunks(
                    from: chosen.commit,
                    to: commit,
                    packagePath: snapshot.info.git.packagePath,
                    in: root
                )
            )
        } catch {
            let reason = "git could not compare \(chosen.commit.prefix(MarkdownSignals.shortLength)) with "
                + "\(commit.prefix(MarkdownSignals.shortLength))"
            let failure = Self.failure(reason, error)
            return SignalInputs(snapshot: snapshot, earlier: earlier, earlierNote: note, gitFailure: failure)
        }
    }

    /// The clean snapshots of `info`'s package, where `info` places it, of
    /// the commits on `line` (oldest first) in which SwiftCloneDetector
    /// ran, with their commits' committer times, in `line`'s order.
    private func cloneSnapshots(
        on line: [(commit: String, time: Int)],
        package info: SnapshotInfo
    ) throws -> [EarlierCandidate] {
        let snapshots = try store.cleanSnapshots(package: info.package, packagePath: info.git.packagePath)
        let ids = Dictionary(snapshots.map { ($0.commit, $0.id) }) { _, last in last }
        return try line.compactMap { entry in
            guard let id = ids[entry.commit] else {
                return nil
            }
            let ran = try store.info(id: id).collectors.contains { run in
                run.name == SwiftCloneDetectorAdapter.name && run.state == .ran
            }
            return ran ? EarlierCandidate(id: id, commit: entry.commit, time: entry.time) : nil
        }
    }
}

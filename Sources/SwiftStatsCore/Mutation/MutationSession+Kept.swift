//
//  MutationSession+Kept.swift
//  SwiftStatsCore
//
//  The results of a run that ran, kept until the scan's snapshot is stored
//  (M6, design §6.4, as built). In a scan that stores its snapshot, a run
//  (or a resume) that ran with a results file leaves `pending.json` naming
//  the results kept in `runs/<id>/`, with the exit's note, the step's
//  warnings and a `--since` run's selection; the copy ends as usual. The
//  workspace removes the record once the snapshot is stored, so a save
//  refused after an hour-long run loses nothing: `scan --mutation
//  --resume` then stores those results without running SwiftMutator,
//  refused as any resume is when the tree, the files the scan parsed or
//  the settings changed, or when the kept results no longer read, and, as
//  a resumed run, failed and forgotten when a `--since` run's header no
//  longer matches its base. A new run discards them, as it discards an
//  interrupted run, saying whose they were.
//

import Foundation

extension MutationSession {
    /// Removes a pending run, which a run that isn't its resume replaces:
    /// a warning saying so when there was one.
    func discardPending() throws(MutationFailure) -> [ScanWarning] {
        let discarded: String
        do {
            guard let pending = try PendingMutationRun.read(in: directory) else {
                return []
            }
            discarded = pending.kept == nil
                ? "the interrupted run of \(pending.startedAt)"
                : "the results of the run of \(pending.startedAt), whose snapshot wasn't stored"
        } catch {
            discarded = "the interrupted run whose \(MutationDirectory.pendingName) doesn't read"
        }
        try PendingMutationRun.remove(in: directory)
        return [Self.warning("discarding \(discarded)")]
    }

    /// Leaves `pending` naming the results `outcome`'s run kept, when the
    /// scan stores its snapshot and the run ran with a results file.
    func keepUntilStored(_ pending: PendingMutationRun, after outcome: Outcome) throws(MutationFailure) {
        guard job.keepsUntilStored, outcome.exit.state == .ran, let file = outcome.resultsFile,
              outcome.results != nil else {
            return
        }
        let kept = PendingMutationRun.Kept(
            resultsFile: file,
            reason: outcome.exit.reason,
            warnings: outcome.warnings,
            selection: outcome.changes?.selection ?? []
        )
        try pending.keeping(kept).write(in: directory)
    }

    /// The outcome of the run that ran and whose snapshot wasn't stored,
    /// from the results it kept, with the lock held and the log started as
    /// `log`; SwiftMutator doesn't run. The record stays until the
    /// snapshot is stored.
    func kept(log: MutationLog) throws(MutationFailure) -> Outcome {
        let pending = try MutationResume.checked(
            root: job.root,
            git: job.git,
            ignoring: job.ignoring,
            files: .scanned(job.scanned),
            settings: job.pendingSettings
        )
        guard pending.mode == .full ? job.base == nil : job.base?.commit == pending.base?.commit else {
            throw MutationFailure(description: PendingMutationRun.noBaseReason)
        }
        let (file, results) = try MutationResume.keptResults(of: pending, root: job.root)
        let kept = pending.kept
        log.note("storing the results of the run of \(pending.startedAt), whose snapshot wasn't stored")
        let report = file.deletingLastPathComponent().appendingPathComponent(MutationCommand.reportName)
        var outcome = Outcome(
            exit: MutationExit(state: .ran, reason: kept?.reason, resumable: false),
            results: results,
            suspects: (try? Data(contentsOf: report)).flatMap { try? SuspectReport.decode($0) } ?? .unjudged,
            resultsFile: kept?.resultsFile,
            fixedFiles: pending.copyFixed,
            warmBuildMilliseconds: nil,
            mutatorMilliseconds: 0,
            warnings: kept?.warnings ?? [],
            changes: pending.mode == .since ? MutationChanges(selection: kept?.selection ?? [], tree: [:]) : nil
        )
        // Stored again later, it would fail the same way.
        if let refusal = job.base?.postRunRefusal(results.facts) {
            outcome = outcome.ending(MutationExit.failed(refusal))
            try PendingMutationRun.remove(in: directory)
        }
        return outcome
    }
}

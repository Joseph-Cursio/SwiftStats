//
//  MutationSession+Resume.swift
//  SwiftStatsCore
//
//  A resumed mutation step (M6, design §1.7): refused, leaving the copy
//  and the record as they were, when the tree differs from the run's, the
//  files its scan parsed included, since the copy holds the run's bytes
//  and SwiftMutator refuses a resume of a changed tree (its exit 5). The
//  kept copy is then checked against the scan again (design §1.2 step
//  4), which can only put back a file of the copy itself that was
//  altered, so nothing is counted as fixed; the configuration is written
//  again as the run recorded it, and SwiftMutator run with the run's
//  command and `--resume <results file>`, with no warm build, since the
//  copy keeps the run's own; the command is the run's own, so a `--since`
//  run is resumed with its `--since`, and its selection is worked out in
//  the copy again for the merge. The record names the file before
//  SwiftMutator starts, when the interrupted scan couldn't. SwiftMutator
//  appends a session to that file, or, when it stops before its first
//  mutant, leaves it as it was and writes a `stopped` line in a run folder
//  of its own, which is read for the reason. A resume that ran is kept and
//  ends the copy and the record as a run does; one that failed keeps both,
//  since the file it continued can still be resumed, and says so unless
//  SwiftMutator itself refused the resume; but one failed because its
//  header no longer matches the base (`MutationBase.postRunRefusal`)
//  keeps neither, since resuming it again would fail the same way.
//

import Foundation

extension MutationSession {
    /// The resume of the pending run, with the lock held and the log
    /// started as `log`.
    func resumed(log: MutationLog) throws(MutationFailure) -> Outcome {
        let resume = try MutationResume.prepare(
            root: job.root,
            git: job.git,
            ignoring: job.ignoring,
            files: .scanned(job.scanned),
            settings: job.pendingSettings
        )
        guard resume.pending.mode == .full ? job.base == nil : job.base?.commit == resume.pending.base?.commit else {
            throw MutationFailure(description: PendingMutationRun.noBaseReason)
        }
        let copy = resume.copy
        // Named before SwiftMutator starts, so a resume that is itself
        // interrupted, whose resumed session adds a run folder, still
        // leaves a record naming the file.
        if resume.pending.resultsFile == nil,
           let path = MutationResume.path(of: resume.resultsFile, inside: copy.work) {
            try resume.pending.naming(resultsFile: path).write(in: directory)
        }
        // The tree is the run's, so this only puts back what the copy
        // itself lost, which git's checkout didn't cause: not counted.
        _ = try MutationWorkCopy.fixHashes(job.scanned, of: job.root, in: copy.project)
        let command = MutationCommand(
            mutator: job.mutator,
            swift: job.swift,
            packageRoot: job.root,
            directory: directory,
            copy: copy,
            log: log
        )
        let changed = try changes(in: copy.project)
        try MutationConfigFile.write(
            swift: job.swift,
            arguments: job.settings?.arguments ?? [],
            to: directory.configuration
        )
        let before = command.runFolders
        let finished = try command.run(resume.pending.command + ["--resume", resume.resultsFile.path])
        let file = try command.resumedResultsFile(
            output: finished.output,
            resuming: resume.resultsFile,
            before: before
        )
        var outcome = try judged(finished, file: file, command: command, warmBuild: nil)
        // A run its header no longer lets merge with the base would fail
        // the same way when resumed again, so it isn't kept for one.
        if outcome.exit.state == .failed, outcome.exit.resumable == false, refusedAfterRun(outcome) == false,
           case .results = Self.read(resume.resultsFile).1 {
            outcome = outcome.ending(outcome.exit.keepingCopy(
                hinting: finished.termination != .exited(MutationExit.resumeRefusedStatus)
            ))
        }
        try record(resume.pending, after: outcome, file: resume.resultsFile, work: copy.work)
        outcome = try outcome.with(changes: withTree(changed, after: outcome, in: copy.project))
        try keepUntilStored(resume.pending, after: outcome)
        return ended(outcome, copy: copy)
    }
}

//
//  MutationSession.swift
//  SwiftStatsCore
//
//  One mutation step (M6, design §1.2 to §1.5), holding the package's
//  mutation lock throughout: refuse while a SwiftMutator run an earlier
//  scan started still runs (`MutationLiveRun`), empty the log, recover a
//  copy an interrupted run left, make the copy, write the configuration,
//  warm the build, run SwiftMutator, find and read its results file,
//  judge how it ended, and
//  for a run that ran, judge its kills with `swift-mutator report` and
//  keep the results file and the report in `runs/<id>/` (the first 16 hex
//  digits of the file's SHA-256). Then the copy ends, its build going back
//  to `build-cache/`, unless the run failed with a results file a resume
//  can continue, whose copy stays for it. `pending.json` (design §1.7) is
//  written just before SwiftMutator starts, then names the results file of
//  a run a resume can continue, or is removed; an interrupted scan, which
//  ends before the step learns how the run ended, does the same once it
//  has stopped SwiftMutator (`MutationSession+Interrupted`). But in a scan
//  that stores its snapshot, a run that ran with a
//  results file names the kept results in it until the snapshot is stored
//  (`MutationSession+Kept`). A run discards a pending run it finds, with a
//  warning; a resume continues it instead, or stores the kept results. A `--since` run (design §6.1) works out
//  SwiftMutator's selection in the copy first, runs with `--since` and its
//  base's full commit, records its mode and base in `pending.json`, and is
//  failed, nothing of it kept, when its results header no longer matches
//  the base (`MutationBase.postRunRefusal`).
//

import Foundation

/// One SwiftMutator run of a package, with its copy and its lock.
struct MutationSession {
    /// What the step gave.
    struct Outcome: Sendable {
        /// How the run ended, as the collector's state.
        let exit: MutationExit
        /// The results file's contents, when it has a readable header,
        /// whether the run ran or failed.
        let results: MutationResults?
        /// What `swift-mutator report` judged of them.
        let suspects: SuspectReport
        /// Where the results file was kept, from the package root; nil
        /// unless the run ran with results.
        let resultsFile: String?
        /// How many files the copy took from the work tree because git
        /// checked them out with other bytes.
        let fixedFiles: Int
        /// How long the warm build took; nil for a resume, which builds
        /// nothing before SwiftMutator.
        let warmBuildMilliseconds: Int?
        /// How long SwiftMutator's run took.
        let mutatorMilliseconds: Int
        /// Problems worth reporting that didn't fail the run.
        let warnings: [ScanWarning]
        /// What a `--since` run's copy changed since the base, with the
        /// copy's tree when the run left no results file; nil for a full
        /// run.
        let changes: MutationChanges?

        /// The outcome with `warning` added.
        func adding(_ warning: ScanWarning) -> Self {
            adding([warning])
        }

        /// The outcome with `added` warnings added after its own.
        func adding(_ added: [ScanWarning]) -> Self {
            Self(
                exit: exit,
                results: results,
                suspects: suspects,
                resultsFile: resultsFile,
                fixedFiles: fixedFiles,
                warmBuildMilliseconds: warmBuildMilliseconds,
                mutatorMilliseconds: mutatorMilliseconds,
                warnings: warnings + added,
                changes: changes
            )
        }

        /// The outcome ending as `ended` instead.
        func ending(_ ended: MutationExit) -> Self {
            Self(
                exit: ended,
                results: results,
                suspects: suspects,
                resultsFile: resultsFile,
                fixedFiles: fixedFiles,
                warmBuildMilliseconds: warmBuildMilliseconds,
                mutatorMilliseconds: mutatorMilliseconds,
                warnings: warnings,
                changes: changes
            )
        }
    }

    /// How many hex digits of a results file's SHA-256 name its run.
    static let runIdentifierLength = 16
    /// The kept results file's name.
    static let keptResults = "results.jsonl"

    /// What the run is given.
    let job: MutationJob
    /// The package's mutation folder.
    let directory: MutationDirectory

    /// Runs `job`'s step, holding the package's mutation lock; a failure
    /// when it couldn't run SwiftMutator or read what it left.
    static func run(_ job: MutationJob) throws(MutationFailure) -> Outcome {
        let folder: MutationDirectory
        do {
            folder = try MutationDirectory(packageRoot: job.root)
        } catch {
            throw MutationWorkCopy.failure("make .swiftstats/mutation", error)
        }
        return try MutationLock.holding(folder.lock) { () throws(MutationFailure) -> Outcome in
            try Self(job: job, directory: folder).locked()
        }
    }

    /// What `file`, a results file or nil, holds, with its bytes.
    static func read(_ file: URL?) -> (Data?, MutationExit.Output) {
        guard let file else {
            return (nil, .noFile)
        }
        guard let data = try? Data(contentsOf: file) else {
            return (nil, .unreadable(MutationFailure(description: "could not read SwiftMutator's results file")))
        }
        do {
            switch try MutationResultsFile.read(data) {
            case .results(let results):
                return (data, .results(results))

            case .stopped(let stop):
                return (data, .stopped(stop))
            }
        } catch {
            return (data, .unreadable(error))
        }
    }

    /// The step, with the lock held: refused, before the log or anything
    /// an earlier run left is touched, while a SwiftMutator run an earlier
    /// scan started still runs in its copy.
    private func locked() throws(MutationFailure) -> Outcome {
        if let refusal = MutationLiveRun.refusal(packageRoot: job.root, git: job.git, in: directory) {
            throw refusal
        }
        let log = try MutationLog.started(at: directory.log)
        if case .resume = job.request {
            if let record = try PendingMutationRun.read(in: directory), record.kept != nil {
                return try kept(log: log)
            }
            return try resumed(log: log)
        }
        let discarded = try discardPending()
        try MutationWorkCopy.recoverLeftover(packageRoot: job.root, git: job.git, in: directory)
        let copy = try MutationWorkCopy.make(
            packageRoot: job.root,
            git: job.git,
            scanned: job.scanned,
            ignoring: job.ignoring,
            in: directory
        )
        let command = MutationCommand(
            mutator: job.mutator,
            swift: job.swift,
            packageRoot: job.root,
            directory: directory,
            copy: copy,
            log: log
        )
        let outcome: Outcome
        do {
            outcome = try tested(with: command)
        } catch {
            try? PendingMutationRun.remove(in: directory)
            try? copy.finish(in: directory)
            throw error
        }
        return ended(outcome.adding(discarded), copy: copy)
    }

    /// Writes the configuration, warms the build, records the pending run,
    /// runs SwiftMutator with `command` and reads what it left. A
    /// `--since` run first works out SwiftMutator's selection in the copy,
    /// and runs with `--since` and the base's full commit.
    private func tested(with command: MutationCommand) throws(MutationFailure) -> Outcome {
        let settings = job.settings
        let configuration = directory.configuration
        let changed = try changes(in: command.copy.project)
        try MutationConfigFile.write(swift: job.swift, arguments: settings?.arguments ?? [], to: configuration)
        let build = try command.warmBuild()
        let arguments = MutationCommand.runArguments(
            configuration: configuration,
            workers: settings?.workers,
            timeout: settings?.timeout
        ) + (job.base.map { ["--since", $0.commit] } ?? [])
        let pending = PendingMutationRun(
            startedAt: Date().formatted(PendingMutationRun.dateFormat),
            commit: job.git.commit,
            dirtyHash: job.git.dirtyHash,
            packagePath: job.git.packagePath,
            mode: job.base == nil ? .full : .since,
            base: job.base.map { PendingMutationRun.Base(commit: $0.commit, collectedAt: $0.report.collectedAt) },
            resultsFile: nil,
            project: MutationResume.path(of: command.copy.project, inside: command.copy.work) ?? "",
            command: arguments,
            settings: job.pendingSettings,
            copyFixed: command.copy.fixedFiles,
            ignoring: job.ignoring,
            scanned: job.scanned
        )
        try pending.write(in: directory)
        let finished = try command.run(arguments, afterStop: afterInterruption(of: pending, in: command.copy))
        let file = try command.resultsFile(output: finished.output)
        let outcome = try judged(finished, file: file, command: command, warmBuild: build)
        try record(pending, after: outcome, file: file, work: command.copy.work)
        let complete = try outcome.with(changes: withTree(changed, after: outcome, in: command.copy.project))
        try keepUntilStored(pending, after: complete)
        return complete
    }

    /// Reads `file`, what the run that ended as `finished` left (nil when
    /// it left none), judges how it ended, and for a run that ran, judges
    /// its kills with `swift-mutator report` and keeps both files; the
    /// warm build took `build` milliseconds, nil when there was none.
    func judged(
        _ finished: MutationCommand.Finished,
        file: URL?,
        command: MutationCommand,
        warmBuild build: Int?
    ) throws(MutationFailure) -> Outcome {
        let (data, contents) = Self.read(file)
        var exit = MutationExit.judge(
            finished.termination,
            output: contents,
            log: finished.output,
            tail: command.lastLines(of: finished.output),
            since: job.base != nil
        )
        let results: MutationResults? = if case .results(let read) = contents { read } else { nil }
        // A `--since` run's header must still match its base (a binary
        // replaced during the run); otherwise nothing of it is merged or
        // kept, and a resume would fail the same way.
        if exit.state == .ran, let results, let refusal = job.base?.postRunRefusal(results.facts) {
            exit = MutationExit.failed(refusal)
        }
        var warnings: [ScanWarning] = []
        var suspects = SuspectReport.unjudged
        var kept: String?
        if exit.state == .ran, let results, let file, let data {
            let report = command.report(of: file)
            suspects = report.suspects
            warnings += [results.skippedLinesWarning.map { ScanWarning(file: nil, message: $0) }, report.warning]
                .compactMap(\.self)
            if let unreported = Self.unreportedWarning(suspects.unreported(among: results.mutants)) {
                warnings.append(unreported)
            }
            kept = try keep(data, report: report.data, sha256: results.sha256)
        }
        return Outcome(
            exit: exit,
            results: results,
            suspects: suspects,
            resultsFile: kept,
            fixedFiles: command.copy.fixedFiles,
            warmBuildMilliseconds: build,
            mutatorMilliseconds: finished.milliseconds,
            warnings: warnings,
            changes: nil
        )
    }

    /// Whether `outcome` failed because its results header no longer
    /// matches the `--since` base: the failure `judged` makes of a run
    /// that ran when `MutationBase.postRunRefusal` refuses it.
    func refusedAfterRun(_ outcome: Outcome) -> Bool {
        guard let results = outcome.results, let refusal = job.base?.postRunRefusal(results.facts) else {
            return false
        }
        return outcome.exit == MutationExit.failed(refusal)
    }

    /// Records `pending` after its run ended as `outcome` with `file`, its
    /// results file (nil when it left none) in the copy's folder `work`:
    /// naming the file when a resume can continue the run, else removing
    /// the record.
    func record(
        _ pending: PendingMutationRun,
        after outcome: Outcome,
        file: URL?,
        work: URL
    ) throws(MutationFailure) {
        guard outcome.exit.resumable, let file, let path = MutationResume.path(of: file, inside: work) else {
            try PendingMutationRun.remove(in: directory)
            return
        }
        try pending.naming(resultsFile: path).write(in: directory)
    }

    /// `outcome`, after ending `copy` unless a resume can continue its
    /// run; a failure to end it becomes a warning.
    func ended(_ outcome: Outcome, copy: MutationWorkCopy) -> Outcome {
        guard outcome.exit.resumable == false else {
            return outcome
        }
        do {
            try copy.finish(in: directory)
        } catch {
            return outcome.adding(Self.warning(error.description))
        }
        return outcome
    }

    /// Keeps `results`, a results file's bytes whose SHA-256 is `sha256`,
    /// and `report`, its JSON report when there is one, in `runs/<id>/`;
    /// the kept file's path from the package root.
    private func keep(_ results: Data, report: Data?, sha256: String) throws(MutationFailure) -> String {
        let identifier = String(sha256.prefix(Self.runIdentifierLength))
        let folder = directory.runs.appendingPathComponent(identifier)
        let reportFile = folder.appendingPathComponent(MutationCommand.reportName)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try results.write(to: folder.appendingPathComponent(Self.keptResults), options: .atomic)
            if let report {
                try report.write(to: reportFile, options: .atomic)
            } else if FileClone.exists(reportFile) {
                try FileClone.remove(reportFile)
            }
        } catch {
            throw MutationWorkCopy.failure("keep the results in .swiftstats/mutation/runs", error)
        }
        return [
            StoreLocation.directoryName, MutationDirectory.name, MutationDirectory.runsName, identifier,
            Self.keptResults
        ].joined(separator: "/")
    }
}

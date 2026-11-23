//
//  MutationSession.swift
//  SwiftStatsCore
//
//  One mutation step (M6, design §1.2 to §1.5), holding the package's
//  mutation lock throughout: empty the log, recover a copy an interrupted
//  run left, make the copy, write the configuration, warm the build, run
//  SwiftMutator, find and read its results file, judge how it ended, and
//  for a run that ran, judge its kills with `swift-mutator report` and
//  keep the results file and the report in `runs/<id>/` (the first 16 hex
//  digits of the file's SHA-256). Then the copy ends, its build going back
//  to `build-cache/`, unless the run failed with a results file a resume
//  can continue, whose copy stays for it.
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
        /// How many scanned files the copy took from the package because
        /// git checked them out with other bytes.
        let fixedFiles: Int
        /// How long the warm build took.
        let warmBuildMilliseconds: Int
        /// How long SwiftMutator's run took.
        let mutatorMilliseconds: Int
        /// Problems worth reporting that didn't fail the run.
        let warnings: [ScanWarning]

        /// The outcome with `warning` added.
        func adding(_ warning: ScanWarning) -> Self {
            Self(
                exit: exit,
                results: results,
                suspects: suspects,
                resultsFile: resultsFile,
                fixedFiles: fixedFiles,
                warmBuildMilliseconds: warmBuildMilliseconds,
                mutatorMilliseconds: mutatorMilliseconds,
                warnings: warnings + [warning]
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
    private static func read(_ file: URL?) -> (Data?, MutationExit.Output) {
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

    /// A scan warning, from the collector, saying `text`.
    private static func warning(_ text: String) -> ScanWarning {
        ScanWarning(file: nil, message: "\(MutationAdapter.name): \(text)")
    }

    /// The step, with the lock held.
    private func locked() throws(MutationFailure) -> Outcome {
        let log = try MutationLog.started(at: directory.log)
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
            try? copy.finish(in: directory)
            throw error
        }
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

    /// Writes the configuration, warms the build, runs SwiftMutator with
    /// `command` and reads what it left.
    private func tested(with command: MutationCommand) throws(MutationFailure) -> Outcome {
        let settings = job.settings
        let configuration = directory.configuration
        try MutationConfigFile.write(swift: job.swift, arguments: settings?.arguments ?? [], to: configuration)
        let build = try command.warmBuild()
        let finished = try command.run(
            MutationCommand.runArguments(
                configuration: configuration,
                workers: settings?.workers,
                timeout: settings?.timeout
            )
        )
        let file = try command.resultsFile(output: finished.output)
        let (data, contents) = Self.read(file)
        let exit = MutationExit.judge(
            finished.termination,
            output: contents,
            log: finished.output,
            tail: command.lastLines(of: finished.output)
        )
        let results: MutationResults? = if case .results(let read) = contents { read } else { nil }
        var warnings = (results?.skippedLinesWarning).map { [ScanWarning(file: nil, message: $0)] } ?? []
        var suspects = SuspectReport.unjudged
        var kept: String?
        if exit.state == .ran, let results, let file, let data {
            let report = command.report(of: file)
            suspects = report.suspects
            warnings += [report.warning].compactMap(\.self)
            if suspects.unreadableKeys > 0 {
                warnings.append(Self.warning(
                    "\(suspects.unreadableKeys) keys of swift-mutator report's JSON don't read, "
                        + "so their kills aren't judged"
                ))
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
            warnings: warnings
        )
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

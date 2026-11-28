//
//  MutationCommand.swift
//  SwiftStatsCore
//
//  The commands of one mutation step (M6, design §1.2 and §1.4), each run
//  in the copy's project folder with `NO_COLOR=1`, standard input
//  `/dev/null`, its output appended to the step's log, and without the
//  variables that would point git at another repository: the warm build
//  (`<swift> build --build-tests`, which keeps `build-cache/` current,
//  since SwiftMutator builds only in copies of its own), the SwiftMutator
//  run, and `swift-mutator report -f json` on its results file. After the
//  run, the results file is found through SwiftMutator's log folder beside
//  the project, which holds one run folder since the copy is new, and is
//  checked against the last `💾 … in <path>` line SwiftMutator printed. A
//  resumed run (`--resume <file>`) appends to the file it continues, in
//  the first session's run folder, and keeps its logs in a run folder of
//  its own, which holds a results file only when the resume stopped
//  before its first mutant: then that file's `stopped` line says why.
//  Reasons name the copy, its folder, the package and SwiftMutator's run
//  folder by placeholders. An interruption stops SwiftMutator's commands
//  by its own policy (SIGTERM, 35 seconds, SIGKILL; design §1.6) and the
//  warm build by the standard one (`StopPolicy`).
//

import Foundation

/// Runs one mutation step's commands.
struct MutationCommand {
    /// A command that ran to its end.
    struct Finished {
        /// How it ended.
        let termination: ProcessTermination
        /// Its output, standard output and standard error together.
        let output: String
        /// How long it took.
        let milliseconds: Int
    }

    /// What `swift-mutator report` gave.
    struct Report {
        /// The JSON report's bytes; nil when it failed or doesn't read.
        let data: Data?
        /// What it judged; every kill unjudged when it failed.
        let suspects: SuspectReport
        /// Why every kill is unjudged; nil when the report read.
        let warning: ScanWarning?
    }

    /// What a reason says for the copy's project folder.
    static let copyPlaceholder = "<copy>"
    /// What it says for the folder holding the copy.
    static let workPlaceholder = "<work>"
    /// What it says for a run folder in SwiftMutator's log folder, whose
    /// name is a minute in the user's locale.
    static let runPlaceholder = "<run>"
    /// The environment every command gets on top of this process's.
    static let environment = ["NO_COLOR": "1"]
    /// The results file's name in the log folder, before any `-<n>`.
    static let resultsPrefix = "results"
    /// Its extension.
    static let resultsExtension = "jsonl"
    /// What the lines naming the results file start with.
    static let savedMarker = "💾"
    /// What comes before the path on such a line.
    static let savedPathLead = " in /"
    /// The report's file in the copy's folder.
    static let reportName = "report.json"
    /// The statuses `report` succeeds with: also SwiftMutator's when
    /// every mutant was a build error.
    static let reportStatuses: Set<Int32> = [0, MutationExit.allBuildErrorsStatus]
    /// What the warnings about an unjudged report end with.
    static let unjudgedNote = "kills only suspect tests made aren't judged"

    /// The `swift-mutator` executable.
    let mutator: URL
    /// The `swift` of the test command and the warm build.
    let swift: URL
    /// The package being scanned.
    let packageRoot: URL
    /// The mutation collector's folder.
    let directory: MutationDirectory
    /// The copy SwiftMutator runs in.
    let copy: MutationWorkCopy
    /// The step's log.
    let log: MutationLog

    /// The directories and tools a reason redacts, innermost first: the
    /// run folders SwiftMutator made, the copy, its folder, the package
    /// and the tools.
    var replacements: [(URL, String)] {
        runFolders.map { ($0, Self.runPlaceholder) } + [
            (copy.project, Self.copyPlaceholder),
            (copy.work, Self.workPlaceholder),
            (packageRoot, CoverageCommand.packagePlaceholder),
            (mutator, mutator.lastPathComponent),
            (swift, swift.lastPathComponent)
        ]
    }

    /// SwiftMutator's log folder, beside the project.
    var logFolder: URL {
        Self.logFolder(of: copy.project)
    }

    /// The run folders in SwiftMutator's log folder, sorted by name; none
    /// before it runs.
    var runFolders: [URL] {
        Self.runFolders(in: logFolder)
    }

    /// SwiftMutator's log folder for the project at `project`, beside it.
    static func logFolder(of project: URL) -> URL {
        project.deletingLastPathComponent().appendingPathComponent(project.lastPathComponent + "_muter_logs")
    }

    /// The run folders in the log folder `folder`, sorted by name; none
    /// when it doesn't exist.
    static func runFolders(in folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .sorted()
            .map(folder.appendingPathComponent)
            .filter(FileClone.isDirectory)
    }

    /// The results files in the run folder `folder`, sorted by name.
    static func resultsFiles(in folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasPrefix(resultsPrefix) && $0.hasSuffix("." + resultsExtension) }
            .sorted()
            .map(folder.appendingPathComponent)
    }

    /// The one results file a run left in the log folder `folder`: nil
    /// unless it holds one run folder holding one results file.
    static func onlyResultsFile(in folder: URL) -> URL? {
        let folders = runFolders(in: folder)
        guard folders.count == 1, let files = folders.first.map(resultsFiles(in:)), files.count == 1 else {
            return nil
        }
        return files.first
    }

    /// `run`'s arguments: the configuration written outside the copy, no
    /// update check, and the workers and time limit when set.
    static func runArguments(configuration: URL, workers: Int?, timeout: Double?) -> [String] {
        ["run", "-c", configuration.path, "--skip-update-check"]
            + (workers.map { ["--workers", String($0)] } ?? [])
            + (timeout.map { ["--timeout", MutationAdapter.seconds($0)] } ?? [])
    }

    /// The path the last `💾 … in <path>` line of `output` names; nil when
    /// none does.
    static func savedPath(in output: String) -> String? {
        let lines = output.split(whereSeparator: \.isNewline).filter { $0.contains(savedMarker) }
        guard let line = lines.last, let lead = line.range(of: savedPathLead) else {
            return nil
        }
        let path = line[line.index(before: lead.upperBound)...].trimmingCharacters(in: .whitespaces)
        return path.isEmpty ? nil : path
    }

    /// How `termination` reads in a reason: `exited <n>` or `ended by
    /// <signal>`.
    static func ended(_ termination: ProcessTermination) -> String {
        switch termination {
        case .exited(let status):
            return "exited \(status)"

        case .signalled(let number):
            return "ended by \(MutationExit.signalName(number))"
        }
    }

    /// The real path of `url`, symbolic links resolved; nil when it
    /// doesn't exist.
    private static func realPath(_ url: URL) -> String? {
        guard let resolved = realpath(url.path, nil) else {
            return nil
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// A scan warning, from the collector, saying `text`.
    private static func warning(_ text: String) -> ScanWarning {
        ScanWarning(file: nil, message: "\(MutationAdapter.name): \(text)")
    }

    /// The report a failed or unread `swift-mutator report` leaves: every
    /// kill unjudged, and a warning saying `why`.
    private static func unjudged(_ why: String) -> Report {
        Report(data: nil, suspects: .unjudged, warning: warning("\(why); \(unjudgedNote)"))
    }

    /// Whether `warning` is one a failed or unread `swift-mutator report`
    /// gives.
    static func isUnjudgedWarning(_ warning: ScanWarning) -> Bool {
        warning.file == nil && warning.message.hasPrefix(MutationAdapter.name + ": ")
            && warning.message.hasSuffix("; " + unjudgedNote)
    }

    /// Builds the copy's tests, so the `.build` SwiftMutator copies, and
    /// `build-cache/` after it, are current; the build's milliseconds, or
    /// a failure with the build's last lines.
    func warmBuild() throws(MutationFailure) -> Int {
        let display = "swift build --build-tests"
        let finished = try logged(swift, ["build", "--build-tests"], display: display, stop: .standard)
        guard finished.termination == .exited(0) else {
            let lines = lastLines(of: finished.output)
            let ending = Self.ended(finished.termination)
            throw MutationFailure(
                description: "the warm build (`\(display)`) \(ending)" + (lines.isEmpty ? "" : ": \(lines)")
            )
        }
        return finished.milliseconds
    }

    /// Runs SwiftMutator with `arguments`: how it ended, its output and
    /// its milliseconds.
    func run(_ arguments: [String]) throws(MutationFailure) -> Finished {
        try logged(mutator, arguments, display: "swift-mutator run", stop: .swiftMutator)
    }

    /// Runs SwiftMutator with `arguments` as `run(_:)` does; an
    /// interruption that stops it then does `afterStop`'s work, since the
    /// step never learns how it ended.
    func run(_ arguments: [String], afterStop: @escaping @Sendable () -> Void) throws(MutationFailure) -> Finished {
        try logged(mutator, arguments, display: "swift-mutator run", stop: .swiftMutator, afterStop: afterStop)
    }

    /// The results file the run that printed `output` left, after checking
    /// the log folder against the path it printed; nil when it left none.
    func resultsFile(output: String) throws(MutationFailure) -> URL? {
        let folders = runFolders
        guard folders.count <= 1 else {
            throw MutationFailure(description: "SwiftMutator's log folder holds \(folders.count) run folders, not one")
        }
        let files = folders.flatMap(Self.resultsFiles(in:))
        guard files.count <= 1 else {
            throw MutationFailure(description: "SwiftMutator's run folder holds \(files.count) results files, not one")
        }
        let found = files.first
        if let saved = Self.savedPath(in: output) {
            try check(saved, against: found, held: "its log folder holds")
        }
        return found
    }

    /// The file to read after a resume of `resumed` that printed `output`,
    /// when the log folder held the run folders `before` as it started:
    /// the results file of a run folder the resume made, which only one
    /// that stopped before its first mutant writes, else `resumed`, which
    /// any path it printed must name.
    func resumedResultsFile(output: String, resuming resumed: URL, before: [URL]) throws(MutationFailure) -> URL {
        let earlier = Set(before.map(\.path))
        let stopped = runFolders.filter { earlier.contains($0.path) == false }.flatMap(Self.resultsFiles(in:))
        guard stopped.count <= 1 else {
            throw MutationFailure(
                description: "SwiftMutator's resumed session left \(stopped.count) results files, not one"
            )
        }
        if let saved = Self.savedPath(in: output) {
            try check(saved, against: resumed, held: "the run it resumed keeps")
        }
        return stopped.first ?? resumed
    }

    /// `swift-mutator report -f json` of `results`: the report's bytes and
    /// what it judges, or every kill unjudged with a warning when it fails
    /// or its JSON doesn't read. It never fails the step.
    func report(of results: URL) -> Report {
        let output = copy.work.appendingPathComponent(Self.reportName)
        let arguments = ["report", results.path, "-f", "json", "-o", output.path]
        let display = "swift-mutator report"
        guard let finished = try? logged(mutator, arguments, display: display, stop: .swiftMutator) else {
            return Self.unjudged("swift-mutator report could not be run")
        }
        guard case .exited(let status) = finished.termination, Self.reportStatuses.contains(status) else {
            return Self.unjudged("swift-mutator report \(Self.ended(finished.termination))")
        }
        guard let data = try? Data(contentsOf: output), let suspects = try? SuspectReport.decode(data) else {
            return Self.unjudged("swift-mutator report's JSON doesn't read")
        }
        return Report(data: data, suspects: suspects, warning: nil)
    }

    /// Fails unless `saved`, a path SwiftMutator printed, names `found`
    /// (`held` says where that is) by its real path.
    private func check(_ saved: String, against found: URL?, held: String) throws(MutationFailure) {
        guard let found, let foundPath = Self.realPath(found),
              Self.realPath(URL(fileURLWithPath: saved)) == foundPath else {
            let named = found.map { redacted($0.path) } ?? "none"
            throw MutationFailure(
                description: "SwiftMutator named its results file \(redacted(saved)), but \(held) \(named)"
            )
        }
    }

    /// `text` with the copy, its folder, the package and the tools
    /// redacted, however each is spelled, but only where a path ends: the
    /// project's path also starts its side folders' names
    /// (`<project>_muter_logs`), which belong to its folder.
    func redacted(_ text: String) -> String {
        PathSpellings.redactedWherePathsEnd(text, replacing: replacements)
    }

    /// The last lines of `output`, redacted and cleaned.
    func lastLines(of output: String) -> String {
        CoverageStderr.cleaned(redacted(output), replacing: [])
    }

    /// Runs `tool` with `arguments` in the project, its output appended to
    /// the log between lines naming it as `display` and saying how it
    /// ended, an interruption stopping it by `policy`, then doing
    /// `afterStop`'s work when given: how it ended, its output and its
    /// milliseconds; a failure when it can't start.
    private func logged(
        _ tool: URL,
        _ arguments: [String],
        display: String,
        stop policy: StopPolicy,
        afterStop: (@Sendable () -> Void)? = nil
    ) throws(MutationFailure) -> Finished {
        log.note(display)
        let start = log.offset()
        let outcome = Stopwatch.time {
            Result {
                try ProcessRunner.runLogged(
                    executable: tool.path,
                    arguments: arguments,
                    in: copy.project,
                    environment: ProcessEnvironment(
                        added: Self.environment,
                        removed: MutationWorkCopy.repositoryVariables
                    ),
                    logging: LoggedRun(log: log.url, stop: policy, afterStop: afterStop)
                )
            }
        }
        switch outcome.result {
        case .success(let termination):
            log.note("\(display) \(Self.ended(termination)) after \(outcome.milliseconds) ms")
            return Finished(
                termination: termination,
                output: log.output(from: start),
                milliseconds: outcome.milliseconds
            )

        case .failure(let error):
            log.note("\(display) could not be run")
            var message = SwiftInferTargetRun.reason(for: error, replacing: replacements)
            if case let ScanError.commandFailed(_, _, text) = error {
                message = redacted(text)
            }
            throw MutationFailure(description: "`\(display)` could not be run: \(message)")
        }
    }
}

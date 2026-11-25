//
//  PeripheryAdapter.swift
//  SwiftStatsCore
//
//  The `periphery` collector (M7, design §5): dead code from outskirts
//  3.28.0, a fork of Periphery, run over the index store the T1 build
//  wrote. It runs only with the T1 group (`scan --index`,
//  `BuildAdapter`). `collectors.periphery.path` names the `outskirts`
//  executable, else `outskirts` on PATH; never `periphery` on PATH, whose
//  JSON and test retention differ. A run asks `outskirts version` (a
//  version other than the one SwiftStats was checked against runs, with
//  a warning), has stale and other-module units moved out of the store
//  (by the `index` collector, or here when it didn't get that far),
//  writes the empty configuration file, then runs outskirts twice in the
//  package root (`PeripheryCommand`), standard input empty, each run's
//  standard output kept in the build directory, and reads both
//  (`PeripheryOutput`). A run that exits other than 0 fails the collector
//  with its last standard-error lines (outskirts' two routine warnings
//  dropped; its kept standard output's when that leaves nothing), as does
//  one warning that a retained module wasn't scanned: that module would
//  retain nothing and its tested API would read as dead. Nothing partial
//  is kept; reasons are free of absolute paths.
//

import Foundation

/// The `periphery` collector.
enum PeripheryAdapter {
    /// A run that can't go on.
    struct Failure: Error, CustomStringConvertible {
        /// Why, for the collector's reason.
        let description: String
    }

    /// The collector's name in a snapshot and in `.swiftstats.yml`.
    static let name = "periphery"
    /// outskirts' executable on PATH.
    static let executableName = "outskirts"
    /// The outskirts version SwiftStats was checked against.
    static let checkedVersion = "3.28.0"
    /// What the note on a run without the index says.
    static let positionNote = "the index didn't run, so results were mapped by position"
    /// What the warning that a retained module wasn't scanned says, as
    /// outskirts 3.28.0 prints it before the modules.
    static let unscannedWarning = "retain_public_modules lists modules that are not scanned"
    /// outskirts' routine warnings, left out of a failure's reason.
    private static let routineWarnings = ["please ensure that Xcode is not running", "implies '--skip-build'"]
    /// How many hex digits of the binary's hash a format failure names.
    private static let hashDigits = 10
    /// The empty file outskirts' standard input is read from.
    private static let nothing = URL(fileURLWithPath: "/dev/null")

    /// The note, and the warning after `periphery: `, on a run of
    /// outskirts `version` when it isn't the version SwiftStats was
    /// checked against; nil when it is.
    static func versionNote(_ version: String) -> String? {
        guard version != checkedVersion else {
            return nil
        }
        return "outskirts \(version) isn't the version SwiftStats was checked against (\(checkedVersion)); "
            + "results may differ"
    }

    /// Runs outskirts as `job` says and records how it went: ran with both
    /// runs' entries, or failed, saying why.
    static func run(_ job: PeripheryJob) -> PeripheryRun {
        var options: [String] = []
        let (outcome, milliseconds) = Stopwatch.time {
            Result { try collect(job, options: &options) }
        }
        let result: AdapterResult
        switch outcome {
        case .success(let output):
            let notes = [versionNote(output.version), job.index.report == nil ? positionNote : nil]
                .compactMap(\.self)
            result = AdapterResult(
                status: CollectorStatus(
                    name: name,
                    state: .ran,
                    version: output.version,
                    reason: notes.isEmpty ? nil : notes.joined(separator: "; "),
                    options: options
                ),
                findings: [],
                warnings: versionNote(output.version).map { [ScanWarning(file: nil, message: "\(name): \($0)")] }
                    ?? []
            )

        case .failure(let error):
            let reason = SwiftInferTargetRun.reason(for: error, replacing: replacements(job))
            result = .failed(name, error: Failure(description: reason), options: options)
        }
        return PeripheryRun(
            timed: TimedAdapterResult(
                result: result,
                executable: job.executable,
                identity: nil,
                milliseconds: milliseconds
            ),
            output: try? outcome.get()
        )
    }

    /// The directories a reason names by placeholder: the build directory,
    /// the toolchain and the package root.
    private static func replacements(_ job: PeripheryJob) -> [(URL, String)] {
        [
            (job.products.scratch, CoverageCommand.buildPlaceholder),
            (job.products.toolchain.directory, CoverageCommand.toolchainPlaceholder),
            (job.scan.root, CoverageCommand.packagePlaceholder)
        ]
    }

    /// Both runs of `job` made and read, `options` set once the retained
    /// modules are known.
    private static func collect(_ job: PeripheryJob, options: inout [String]) throws -> PeripheryOutput {
        let products = job.products
        let version = try self.version(of: job)
        let units = try job.index.report.map { PeripheryUnits(index: $0, localUSRs: job.index.localUSRs) }
            ?? PeripheryUnits(
                products: products,
                root: job.scan.root,
                opening: job.opening,
                moving: job.index.quarantineRan == false
            )
        let c99 = Dictionary(products.package.targets.map { ($0.name, $0.c99name) }) { first, _ in first }
        let retained = units.retained.compactMap { c99[$0] }.sorted(by: CodePointOrder.precedes)
        options = PeripheryCommand.Run.ordered.map { PeripheryCommand.option($0, retained: retained) }
            + [PeripheryCommand.retainOption(targets: units.retained), "classes: " + PeripheryOutput.rule]
        let configuration = products.scratch.appendingPathComponent(PeripheryCommand.configurationName)
        do {
            try Data().write(to: configuration)
        } catch {
            throw Failure(description: "could not write the empty \(configuration.path): \(error.localizedDescription)")
        }
        let context = PeripheryOutput.Context(
            root: IndexStoreReader.realPath(job.scan.root.path),
            scratch: products.scratch.path.precomposedStringWithCanonicalMapping,
            package: products.package,
            modules: products.modules,
            files: Set(job.scan.files.map(\.path)),
            changedFiles: Set(products.changedFiles),
            records: job.scan.records,
            localUSRs: units.localUSRs
        )
        var entries: [PeripheryEntry] = []
        for run in PeripheryCommand.Run.ordered {
            let arguments = PeripheryCommand.arguments(
                run,
                scratch: products.scratch.path,
                describe: products.describeFile.path,
                configuration: configuration.path,
                retained: retained
            )
            let data = try scan(run, arguments: arguments, job: job)
            do {
                entries += try PeripheryOutput.decode(data, run: run, context: context)
            } catch let failure as PeripheryOutput.FormatFailure {
                let hash = ContentHash.sha256(ofFileAt: job.executable.resolvingSymlinksInPath()) ?? "unknown"
                throw Failure(
                    description: "outskirts \(version) (sha256:\(hash.prefix(hashDigits))) \(failure.description)"
                )
            }
        }
        return PeripheryOutput(version: version, retained: units.retained, entries: entries)
    }

    /// The first non-empty line `outskirts version` prints.
    private static func version(of job: PeripheryJob) throws -> String {
        let output = try launch(job, arguments: ["version"], output: nil, display: "outskirts version")
        let text = String(bytes: output.output, encoding: .utf8) ?? ""
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.isEmpty == false }
        guard output.termination == .exited(0), let line else {
            throw Failure(description: "outskirts version " + ending(output, job: job))
        }
        return line
    }

    /// The JSON `run`, made with `arguments`, prints: its standard output,
    /// kept in the build directory; a failure when it doesn't exit 0 or
    /// warns that a retained module wasn't scanned.
    private static func scan(_ run: PeripheryCommand.Run, arguments: [String], job: PeripheryJob) throws -> Data {
        let file = job.products.scratch.appendingPathComponent(PeripheryCommand.outputName(run))
        let display = "outskirts scan (\(run.rawValue))"
        let output = try launch(job, arguments: arguments, output: file, display: display)
        guard output.termination == .exited(0) else {
            throw Failure(description: display + " " + ending(output, job: job, standardOutput: file))
        }
        let warned = output.errorText.split(whereSeparator: \.isNewline).first { $0.contains(unscannedWarning) }
        if let warned {
            let listed = warned.split(separator: ":").last.map(String.init) ?? ""
            let modules = listed.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .map { job.products.modules[$0] ?? $0 }
            throw Failure(description: "outskirts didn't scan retained module(s) " + modules.joined(separator: ", "))
        }
        do {
            return try Data(contentsOf: file)
        } catch {
            throw Failure(description: "could not read \(file.path): \(error.localizedDescription)")
        }
    }

    /// Runs `job`'s outskirts with `arguments` in the package root,
    /// standard input empty and standard output written to `output` (kept
    /// when nil); a failure shown as `display` when it can't start.
    private static func launch(
        _ job: PeripheryJob,
        arguments: [String],
        output: URL?,
        display: String
    ) throws -> ProcessOutput {
        do {
            return try ProcessRunner.runToEnd(
                executable: job.executable.path,
                arguments: arguments,
                in: job.scan.root,
                input: nothing,
                writingOutputTo: output
            )
        } catch {
            let message: String
            if case let ScanError.commandFailed(_, _, text) = error {
                message = text
            } else {
                message = "\(error)"
            }
            let tool = [(job.executable, executableName)]
            let redacted = SwiftInferTargetRun.redacted(message, replacing: tool)
            throw Failure(description: "\(display) could not be run: \(redacted)")
        }
    }

    /// How a run that left `output` ended, for a failure's reason:
    /// `exited <n>` or `was stopped by signal <n>`, then its standard
    /// error without outskirts' routine warnings (its standard output when
    /// that leaves nothing: the file `standardOutput` when the run wrote
    /// it there, else what `output` kept), cleaned to its last lines.
    private static func ending(
        _ output: ProcessOutput,
        job: PeripheryJob,
        standardOutput file: URL? = nil
    ) -> String {
        let how: String
        switch output.termination {
        case .exited(let status):
            how = "exited \(status)"

        case .signalled(let signal):
            how = "was stopped by signal \(signal)"
        }
        let kept = output.errorText.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .filter { line in routineWarnings.contains { line.contains($0) } == false }
            .joined(separator: "\n")
        var reason = CoverageStderr.cleaned(kept, replacing: replacements(job))
        if reason.isEmpty {
            let written = file.flatMap { try? Data(contentsOf: $0) } ?? output.output
            let standardOutput = String(bytes: written, encoding: .utf8) ?? ""
            reason = CoverageStderr.cleaned(standardOutput, replacing: replacements(job))
        }
        return how + (reason.isEmpty ? "" : ": \(reason)")
    }
}

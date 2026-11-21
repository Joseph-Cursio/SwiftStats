//
//  CoverageCommand.swift
//  SwiftStatsCore
//
//  Runs a coverage run's commands in the package root (M5), and turns a
//  failed one into a reason: the command as `swift build …`, its exit
//  status and its standard error cleaned (`CoverageStderr`), with the
//  package, the build directory and the toolchain redacted.
//

import Foundation

/// Runs the coverage run's commands for one package.
struct CoverageCommand {
    /// What a reason says for the package root.
    static let packagePlaceholder = "<package>"
    /// What it says for the build directory.
    static let buildPlaceholder = "<build>"
    /// What it says for the toolchain's directory.
    static let toolchainPlaceholder = "<toolchain>"

    /// The package root, where every command runs.
    let root: URL
    /// The build directory, `<root>/.swiftstats/coverage-build`.
    let build: URL
    /// The toolchain's directory; nil before it is known.
    let toolchain: URL?

    /// Each directory a reason redacts, innermost first, with its placeholder.
    var replacements: [(URL, String)] {
        [(build, Self.buildPlaceholder), (root, Self.packagePlaceholder)]
            + (toolchain.map { [($0, Self.toolchainPlaceholder)] } ?? [])
    }

    /// `tool` run with `arguments` as a reason shows it: the tool's name and
    /// the arguments, redacted.
    func display(_ tool: URL, _ arguments: [String]) -> String {
        redacted(([tool.lastPathComponent] + arguments).joined(separator: " "))
    }

    /// `text` with the package, the build directory and the toolchain
    /// redacted.
    func redacted(_ text: String) -> String {
        SwiftInferTargetRun.redacted(text, replacing: replacements)
    }

    /// Runs `tool` with `arguments` and returns what it left; a failure
    /// shown as `display` when it can't start or exits non-zero.
    func run(_ tool: URL, _ arguments: [String], display: String) throws -> ProcessOutput {
        let output = try runToEnd(tool, arguments, display: display)
        guard output.status == 0 else {
            throw failure(display, output: output)
        }
        return output
    }

    /// Runs `tool` with `arguments` to its end, whatever its exit status;
    /// a failure shown as `display` only when it can't start.
    func runToEnd(_ tool: URL, _ arguments: [String], display: String) throws -> ProcessOutput {
        do {
            return try ProcessRunner.runToEnd(executable: tool.path, arguments: arguments, in: root)
        } catch {
            throw launchFailure(display, tool: tool, error: error)
        }
    }

    /// Runs `tool` with `arguments`, writing its standard output to
    /// `output`; a failure shown as `display` when it can't start, when
    /// `output` can't be created, or when it exits non-zero.
    func run(_ tool: URL, _ arguments: [String], writingOutputTo output: URL, display: String) throws {
        let result: ProcessOutput
        do {
            result = try ProcessRunner.runToEnd(
                executable: tool.path,
                arguments: arguments,
                in: root,
                writingOutputTo: output
            )
        } catch {
            throw launchFailure(display, tool: tool, error: error)
        }
        guard result.status == 0 else {
            throw failure(display, output: result)
        }
    }

    /// The failure of the command shown as `display`, which couldn't be
    /// run for `error`: the display and the error's own text, with `tool`
    /// cut to its name and the directories redacted, never the full
    /// command line `ScanError.commandFailed` holds, whose tool path may
    /// lie outside them (the resolved `swift`, `xcrun`).
    func launchFailure(_ display: String, tool: URL, error: any Error) -> CoverageFailure {
        let message: String
        if case let ScanError.commandFailed(_, _, text) = error {
            message = text
        } else {
            message = SwiftInferTargetRun.reason(for: error, replacing: [])
        }
        let reason = SwiftInferTargetRun.redacted(message, replacing: [(tool, tool.lastPathComponent)] + replacements)
        return CoverageFailure(description: "`\(display)` could not be run: \(reason)")
    }

    /// The failure of the command shown as `display`, which left `output`:
    /// its exit status and its standard error cleaned, or its standard
    /// output when standard error is empty (some tools explain failures
    /// there).
    func failure(_ display: String, output: ProcessOutput) -> CoverageFailure {
        var reason = CoverageStderr.cleaned(output.errorText, replacing: replacements)
        if reason.isEmpty {
            let standardOutput = String(bytes: output.output, encoding: .utf8) ?? ""
            reason = CoverageStderr.cleaned(standardOutput, replacing: replacements)
        }
        return CoverageFailure(
            description: "`\(display)` exited with status \(output.status)" + (reason.isEmpty ? "" : ": \(reason)")
        )
    }
}

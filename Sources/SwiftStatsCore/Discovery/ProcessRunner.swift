//
//  ProcessRunner.swift
//  SwiftStatsCore
//
//  Runs an external command and returns its standard output. Standard error is
//  drained concurrently so a chatty tool can't fill its pipe and block while
//  SwiftStats is still waiting on standard output.
//

import Foundation

/// Runs external commands for collectors and loaders.
enum ProcessRunner {
    /// How many lines of a failing command's output to keep (PRD §6.5).
    private static let maximumReasonLines = 20

    /// Runs `executable` with `arguments` in `directory` and returns its
    /// standard output. Throws `ScanError.commandFailed` on a non-zero exit.
    static func run(executable: String, arguments: [String], in directory: URL) throws -> Data {
        try run(executable: executable, arguments: arguments, in: directory, accepting: [0]).output
    }

    /// Runs `executable` with `arguments` in `directory`. Throws
    /// `ScanError.commandFailed` when it can't start or exits with a status
    /// outside `accepted`; some tools exit non-zero to say they found
    /// something (PRD §6.5).
    static func run(
        executable: String,
        arguments: [String],
        in directory: URL,
        accepting accepted: Set<Int32>
    ) throws -> ProcessOutput {
        try run(executable: executable, arguments: arguments, in: directory, accepting: accepted, environment: [:])
    }

    /// Runs `executable` with `arguments` in `directory`, with `environment`
    /// added to this process's, and returns its standard output. Throws
    /// `ScanError.commandFailed` on a non-zero exit.
    static func run(
        executable: String,
        arguments: [String],
        in directory: URL,
        environment: [String: String]
    ) throws -> Data {
        try run(executable: executable, arguments: arguments, in: directory, accepting: [0], environment: environment)
            .output
    }

    /// Runs `executable` with `arguments` in `directory`, in this process's
    /// environment without the variables named in `removed` and with
    /// `environment` added, and returns its standard output. Throws
    /// `ScanError.commandFailed` on a non-zero exit.
    static func run(
        executable: String,
        arguments: [String],
        in directory: URL,
        environment: [String: String],
        removing removed: Set<String>
    ) throws -> Data {
        try run(
            executable: executable,
            arguments: arguments,
            in: directory,
            accepting: { $0 == 0 },
            environment: ProcessEnvironment(added: environment, removed: removed)
        ).output
    }

    /// Runs `executable` with `arguments` in `directory`, reading standard
    /// input from the file at `input`, and returns its standard output.
    /// Throws `ScanError.commandFailed` on a non-zero exit.
    static func run(executable: String, arguments: [String], in directory: URL, input: URL) throws -> Data {
        try run(
            executable: executable,
            arguments: arguments,
            in: directory,
            accepting: { $0 == 0 },
            environment: .inherited,
            input: input
        ).output
    }

    /// Runs `executable` as `run(executable:arguments:in:accepting:)` does,
    /// with `environment` added to this process's.
    static func run(
        executable: String,
        arguments: [String],
        in directory: URL,
        accepting accepted: Set<Int32>,
        environment: [String: String]
    ) throws -> ProcessOutput {
        try run(
            executable: executable,
            arguments: arguments,
            in: directory,
            accepting: accepted.contains,
            environment: ProcessEnvironment(added: environment, removed: []),
            input: nil
        )
    }

    /// Runs `executable` with `arguments` in `directory` to its end and
    /// returns what it left, whatever its exit status, for a caller that
    /// judges the status itself (the coverage run, M5). Throws
    /// `ScanError.commandFailed` only when it can't start.
    static func runToEnd(executable: String, arguments: [String], in directory: URL) throws -> ProcessOutput {
        try run(
            executable: executable,
            arguments: arguments,
            in: directory,
            accepting: { _ in true },
            environment: .inherited
        )
    }

    /// Runs `executable` as `runToEnd(executable:arguments:in:)` does, with
    /// standard output written to the file at `output` (created or
    /// replaced) rather than kept in memory: the returned output is empty.
    static func runToEnd(
        executable: String,
        arguments: [String],
        in directory: URL,
        writingOutputTo output: URL
    ) throws -> ProcessOutput {
        try run(
            executable: executable,
            arguments: arguments,
            in: directory,
            accepting: { _ in true },
            environment: .inherited,
            output: output
        )
    }

    /// Runs `executable` as `run(executable:arguments:in:accepting:)` does,
    /// in this process's environment changed by `environment`, standard
    /// input read from `input` and standard output written to the file at
    /// `output` when given; `accepts` says which exit statuses succeed.
    private static func run(
        executable: String,
        arguments: [String],
        in directory: URL,
        accepting accepts: (Int32) -> Bool,
        environment: ProcessEnvironment,
        input: URL? = nil,
        output outputFile: URL? = nil
    ) throws -> ProcessOutput {
        let process = Process()
        if let input {
            guard let handle = try? FileHandle(forReadingFrom: input) else {
                throw ScanError.commandFailed(executable, -1, "could not read \(input.path)")
            }
            process.standardInput = handle
        }
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        if environment.isInherited == false {
            process.environment = environment.applied(to: ProcessInfo.processInfo.environment)
        }

        // Standard error goes to a file, so only one stream is read while
        // the command runs and neither can fill up and block it.
        let command = ([executable] + arguments).joined(separator: " ")
        let errorFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftStats-stderr-\(UUID().uuidString)")
        ScratchRegistry.shared.track(errorFile)
        guard FileManager.default.createFile(atPath: errorFile.path, contents: nil),
              let errorHandle = try? FileHandle(forWritingTo: errorFile) else {
            ScratchRegistry.shared.remove(errorFile)
            throw ScanError.commandFailed(command, -1, "could not create a file for standard error")
        }
        defer {
            try? errorHandle.close()
            ScratchRegistry.shared.remove(errorFile)
        }
        let outputPipe = Pipe()
        let outputHandle = try outputFile.map { try handle(writingTo: $0, command: command) }
        defer { try? outputHandle?.close() }
        process.standardOutput = outputHandle ?? outputPipe
        process.standardError = errorHandle

        // Registered while it runs, so an interruption terminates it.
        do {
            try ScratchRegistry.shared.start(process)
        } catch {
            throw ScanError.commandFailed(command, -1, error.localizedDescription)
        }
        let output = outputHandle == nil ? outputPipe.fileHandleForReading.readDataToEndOfFile() : Data()
        process.waitUntilExit()
        ScratchRegistry.shared.finished(process)

        let errorText = (try? String(contentsOf: errorFile, encoding: .utf8)) ?? ""
        guard accepts(process.terminationStatus) else {
            // Some tools (swiftly, for one) explain failures on standard
            // output, so fall back to it when standard error is empty.
            let outputText = String(bytes: output, encoding: .utf8) ?? ""
            let reason = errorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? outputText : errorText
            throw ScanError.commandFailed(command, process.terminationStatus, lastLines(of: reason))
        }
        return ProcessOutput(status: process.terminationStatus, output: output, errorText: errorText)
    }

    /// A handle writing to `file`, created or emptied, for `command`'s
    /// standard output.
    private static func handle(writingTo file: URL, command: String) throws -> FileHandle {
        guard FileManager.default.createFile(atPath: file.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: file) else {
            throw ScanError.commandFailed(command, -1, "could not create \(file.path)")
        }
        return handle
    }

    /// The last `maximumReasonLines` non-empty lines of `text`, joined.
    private static func lastLines(of text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false }
            .suffix(maximumReasonLines)
            .joined(separator: "\n")
    }
}

//
//  ProcessRunner.swift
//  SwiftStatsCore
//
//  Runs an external command and returns its standard output. Standard error is
//  drained concurrently so a chatty tool can't fill its pipe and block while
//  SwiftStats is still waiting on standard output.
//

import Dispatch
import Foundation

/// Runs external commands for collectors and loaders.
enum ProcessRunner {
    /// How many lines of a failing command's output to keep (PRD §6.5).
    private static let maximumReasonLines = 20

    /// Runs `executable` with `arguments` in `directory` and returns its
    /// standard output. Throws `ScanError.commandFailed` on a non-zero exit.
    static func run(executable: String, arguments: [String], in directory: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        let errorBox = DataBox()
        let errorReading = DispatchGroup()
        DispatchQueue.global().async(group: errorReading) {
            errorBox.data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        }

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        errorReading.wait()

        guard process.terminationStatus == 0 else {
            // Some tools (swiftly, for one) explain failures on standard
            // output, so fall back to it when standard error is empty.
            let errorText = String(bytes: errorBox.data, encoding: .utf8) ?? ""
            let outputText = String(bytes: output, encoding: .utf8) ?? ""
            let reason = errorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? outputText : errorText
            let command = ([executable] + arguments).joined(separator: " ")
            throw ScanError.commandFailed(command, process.terminationStatus, lastLines(of: reason))
        }
        return output
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

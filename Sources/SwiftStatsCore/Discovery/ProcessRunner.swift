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
            let message = String(bytes: errorBox.data, encoding: .utf8) ?? ""
            let command = ([executable] + arguments).joined(separator: " ")
            throw ScanError.commandFailed(command, process.terminationStatus, message)
        }
        return output
    }
}
